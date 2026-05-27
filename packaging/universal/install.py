#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""
AppGrid universal-package installer.

Extracts the bundled `files/` tree into `~/.local/`, where Plasma 6 picks
up user-installed plasmoids alongside system ones. Never installs OS
packages itself — if runtime dependencies are missing, prints the
per-distro install command and exits.

Distro detection + package mapping lives in distros.toml so adding a new
distro doesn't require touching this script.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PAYLOAD_DIR = SCRIPT_DIR / "files"
MANIFEST_FILE = SCRIPT_DIR / "MANIFEST"
SHA256SUMS_FILE = SCRIPT_DIR / "SHA256SUMS"
DISTROS_TOML = SCRIPT_DIR / "distros.toml"
VERSION_FILE = SCRIPT_DIR / "VERSION"

USER_PREFIX = Path.home() / ".local"
USER_MANIFEST = USER_PREFIX / "share" / "appgrid" / "MANIFEST"

MAX_PAYLOAD_FILES = 5000
MAX_PAYLOAD_BYTES = 100 * 1024 * 1024
SHA256SUMS_RE = re.compile(r"^([0-9a-f]{64})\s+(\S.*)$")
VERSION_RE = re.compile(r"^v?\d+(\.\d+){0,3}(-[0-9A-Za-z.\-]+)?(\+[0-9A-Za-z.\-]+)?$")

# Qt's plugin search path is baked at build time to /usr/lib/qt6/plugins
# and doesn't look under ~/.local/. plasma-workspace sources every *.sh
# in this dir at session start, so we drop a tiny script there.
PLASMA_ENV_DIR = Path.home() / ".config" / "plasma-workspace" / "env"
PLASMA_ENV_FILE = PLASMA_ENV_DIR / "appgrid-user-local.sh"

# Allowlist of absolute paths uninstall is permitted to touch. Tampered
# MANIFEST entries pointing anywhere else are rejected.
ALLOWED_ABS_EXTRAS = frozenset({PLASMA_ENV_FILE})

# System-wide locations that an existing distro-packaged AppGrid lands
# in. Plasma scans both system and user plasmoid dirs; if it finds the
# applet ID twice it picks whichever its discovery hits first, which is
# usually the system one — leaving the user on the old version and
# defeating the universal install. We refuse to overwrite this footgun.
SYSTEM_APPGRID_PATHS = (
    Path("/usr/share/plasma/plasmoids/dev.xarbit.appgrid"),
    Path("/usr/share/plasma/plasmoids/dev.xarbit.appgrid.panel"),
)

# Per-distro-family hint for the uninstall command. Keyed by the table
# name in distros.toml — unknown names fall through to the generic list.
UNINSTALL_HINTS = {
    "arch":         "sudo pacman -R plasma6-applets-appgrid",
    "fedora":       "sudo dnf remove plasma-applet-appgrid",
    "openmandriva": "sudo dnf remove plasma-applet-appgrid",
    "debian":       "sudo apt remove plasma-applet-appgrid",
    "opensuse":     "sudo zypper remove plasma6-applet-appgrid",
    "gentoo":       "sudo emerge -C kde-misc/plasma6-applet-appgrid",
}
PLASMA_ENV_CONTENT = """\
#!/bin/sh
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Added by AppGrid's universal installer. Plasma-workspace sources this
# at session start so plasmashell can discover the .so under ~/.local/.
# Safe to remove if you uninstall AppGrid.

_appgrid_path="$HOME/.local/lib/qt6/plugins"
case ":${QT_PLUGIN_PATH:-}:" in
    *":$_appgrid_path:"*) ;;
    *) export QT_PLUGIN_PATH="$_appgrid_path${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" ;;
esac
unset _appgrid_path
"""


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg: str = "") -> None:
    print(msg)


def confirm(prompt: str, *, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    reply = input(f"{prompt} [y/N] ").strip().lower()
    return reply in ("y", "yes")


def refuse_if_root() -> None:
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        die("refusing to install as root — the universal package goes into "
            "the invoking user's ~/.local/. Run as your normal user; sudo "
            "is never needed.")


def validate_home() -> None:
    home = Path.home()
    if not home.is_absolute() or home == Path("/") or str(home) == "":
        die(f"refusing to install: $HOME ({home}) is not a sane user "
            f"directory.")


def safe_rel(rel: str) -> Path:
    """Reject `..` traversal and resolve under USER_PREFIX."""
    candidate = (USER_PREFIX / rel).resolve()
    base = USER_PREFIX.resolve()
    try:
        candidate.relative_to(base)
    except ValueError:
        die(f"payload path escapes USER_PREFIX: {rel!r} -> {candidate}")
    if any(part == ".." for part in Path(rel).parts):
        die(f"payload path contains '..': {rel!r}")
    return candidate


def safe_extra(abs_path: str) -> Path:
    """Reject absolute paths not in ALLOWED_ABS_EXTRAS."""
    candidate = Path(abs_path).resolve()
    if candidate not in {p.resolve() for p in ALLOWED_ABS_EXTRAS}:
        die(f"refusing to handle absolute path outside the allowlist: "
            f"{abs_path}")
    return candidate


# -- Distro detection ------------------------------------------------------

def parse_os_release() -> dict[str, str]:
    """Minimal /etc/os-release parser (KEY=value, optionally quoted)."""
    path = Path("/etc/os-release")
    if not path.is_file():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def detect_distro(distros: dict[str, dict]) -> tuple[str, dict]:
    """Return (table-name, table) for the active distro, or ('generic', ...).

    Matching order:
      1. VARIANT_ID exact (atomic variant beats its base distro: Kinoite > Fedora)
      2. VARIANT_ID prefix (covers families like aurora-dx, bazzite-deck-nvidia)
      3. ID exact
      4. ID prefix
      5. ID_LIKE exact
      6. ID_LIKE prefix
      7. fallback to [generic]

    Tables list explicit values under `aliases` and prefix patterns under
    `prefixes`. A prefix matches when the os-release token starts with it
    (e.g. prefix `aurora-` matches VARIANT_ID `aurora-dx-nvidia`).
    """
    os_release = parse_os_release()
    variant = os_release.get("VARIANT_ID", "").strip().lower()
    primary = [os_release.get("ID", "").strip().lower()]
    likes = [s.strip().lower() for s in os_release.get("ID_LIKE", "").split() if s.strip()]

    def _match_exact(token: str) -> tuple[str, dict] | None:
        if not token:
            return None
        for name, table in distros.items():
            if token in table.get("aliases", []):
                return name, table
        return None

    def _match_prefix(token: str) -> tuple[str, dict] | None:
        if not token:
            return None
        for name, table in distros.items():
            for prefix in table.get("prefixes", []):
                if token.startswith(prefix):
                    return name, table
        return None

    for matcher in (_match_exact, _match_prefix):
        result = matcher(variant)
        if result:
            return result

    for ids in (primary, likes):
        for matcher in (_match_exact, _match_prefix):
            for token in ids:
                result = matcher(token)
                if result:
                    return result

    return "generic", distros.get("generic", {})


def system_appgrid_present() -> list[Path]:
    """Return the subset of SYSTEM_APPGRID_PATHS that exist on disk."""
    return [p for p in SYSTEM_APPGRID_PATHS if p.exists()]


def warn_on_system_install(name: str, *, allow_coexist: bool) -> None:
    """Refuse the install (or warn) when a distro package is already on
    the system. Plasma can't reliably load two copies of the same applet
    ID — see SYSTEM_APPGRID_PATHS comment."""
    found = system_appgrid_present()
    if not found:
        return
    info()
    info("error: AppGrid is already installed system-wide via your package manager:")
    for p in found:
        info(f"  - {p}")
    info()
    info("Plasma can't reliably load two copies of the same applet ID — please")
    info("remove the system package first so the universal install can take over.")
    info()
    hint = UNINSTALL_HINTS.get(name)
    if hint:
        info("Suggested for your distro:")
        info(f"  {hint}")
    else:
        info("Try one of these (whichever package manager your distro uses):")
        for h in dict.fromkeys(UNINSTALL_HINTS.values()):
            info(f"  {h}")
    info()
    if allow_coexist:
        info("--allow-coexist set; proceeding anyway. Plasma may still load the")
        info("system copy on next session start.")
        info()
        return
    info("Rerun with --allow-coexist to proceed anyway (not recommended).")
    sys.exit(2)


def plasma_present() -> bool:
    """plasmashell on PATH = Plasma 6 session bin available."""
    return shutil.which("plasmashell") is not None


def unresolved_dependencies() -> list[str]:
    """ldd each bundled .so; return libs the dynamic linker can't resolve."""
    if not shutil.which("ldd"):
        return []

    missing: set[str] = set()
    for so in PAYLOAD_DIR.rglob("*.so"):
        try:
            out = subprocess.run(["ldd", str(so)], capture_output=True,
                                 text=True, check=False).stdout
        except OSError:
            continue
        for line in out.splitlines():
            line = line.strip()
            if "=> not found" in line:
                lib = line.split("=>")[0].strip()
                if lib:
                    missing.add(lib)
    return sorted(missing)


def package_version() -> str:
    """Read + validate the VERSION file stamped by build-package.sh."""
    if not VERSION_FILE.is_file():
        return "unknown"
    raw = VERSION_FILE.read_text(errors="replace").strip()
    if not raw:
        return "unknown"
    if len(raw) > 64 or "\n" in raw:
        die(f"refusing to install: VERSION file is malformed (length "
            f"{len(raw)} or contains newlines).")
    if not VERSION_RE.match(raw):
        die(f"refusing to install: VERSION file content {raw!r} doesn't "
            f"match the expected version format.")
    return raw


def read_existing_manifest() -> tuple[str, set[str], set[str]] | None:
    """Returns (version, rel_paths, abs_paths) or None. Validates each entry."""
    if not USER_MANIFEST.is_file():
        return None
    version = "unknown"
    rel: set[str] = set()
    abs_: set[str] = set()
    for n, raw in enumerate(USER_MANIFEST.read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# version:"):
                version = line.split(":", 1)[1].strip() or "unknown"
            continue
        if line.startswith("@"):
            entry = line[1:]
            safe_extra(entry)
            abs_.add(entry)
        else:
            safe_rel(line)
            rel.add(line)
    return version, rel, abs_


def version_tuple(v: str) -> tuple[int, ...]:
    """Numeric tuple for ordering; strips leading 'v' and non-numeric tail."""
    parts: list[int] = []
    for seg in v.lstrip("v").split("."):
        num = ""
        for ch in seg:
            if ch.isdigit():
                num += ch
            else:
                break
        if num:
            parts.append(int(num))
        else:
            break
    return tuple(parts)


def describe_transition(old: str, new: str) -> str:
    if old == "unknown" or new == "unknown":
        return f"{old} -> {new} (reinstall)"
    if old == new:
        return f"{new} -> {new} (reinstall)"
    return f"{old} -> {new}" + (" (downgrade)" if version_tuple(new) < version_tuple(old) else "")


def verify_sha256sums() -> None:
    """Verify SHA256SUMS; refuse install if any listed file mismatches or
    any payload file is present but not listed (defeats attacker dropping
    extra unverified binaries into files/).
    """
    if not SHA256SUMS_FILE.is_file():
        die(f"missing SHA256SUMS in this package ({SHA256SUMS_FILE}). "
            f"Refusing to install without an integrity manifest. If you "
            f"built this tarball yourself, re-run packages/universal/"
            f"build-package.sh which generates SHA256SUMS; if you "
            f"downloaded it, the tarball is corrupt or tampered.")
    listed_paths: set[str] = set()
    for n, raw in enumerate(SHA256SUMS_FILE.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = SHA256SUMS_RE.match(line)
        if not match:
            die(f"malformed SHA256SUMS line {n}: {raw!r}\n"
                f"  expected: <64 hex chars> <whitespace> <path>")
        expected, rel = match.group(1), match.group(2).strip()
        if any(part == ".." for part in Path(rel).parts) or Path(rel).is_absolute():
            die(f"SHA256SUMS line {n} contains an unsafe path: {rel!r}")
        target = SCRIPT_DIR / rel
        if not target.is_file():
            die(f"missing payload file listed in SHA256SUMS: {rel}")
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != expected:
            die(f"SHA256 mismatch for {rel}\n"
                f"  expected: {expected}\n  actual:   {digest}")
        listed_paths.add(rel)

    payload_paths = {str(p.relative_to(SCRIPT_DIR))
                     for p in PAYLOAD_DIR.rglob("*") if p.is_file()}
    uncovered = payload_paths - listed_paths
    if uncovered:
        die("the following payload files are present but NOT covered by "
            "SHA256SUMS:\n  " + "\n  ".join(sorted(uncovered))
            + "\nRefusing to install — the package has unverified files.")


def install_payload(*, dry_run: bool) -> list[Path]:
    """Copy PAYLOAD_DIR/* into USER_PREFIX/*. Refuse symlinks (escape vector
    via shutil.copy2 following them) and traversal paths."""
    installed: list[Path] = []
    total_bytes = 0
    for src in PAYLOAD_DIR.rglob("*"):
        if src.is_symlink():
            die(f"refusing to install: payload contains a symlink: "
                f"{src.relative_to(PAYLOAD_DIR)}")
        if not src.is_file():
            continue
        rel = src.relative_to(PAYLOAD_DIR)
        target = safe_rel(str(rel))
        total_bytes += src.stat().st_size
        if total_bytes > MAX_PAYLOAD_BYTES:
            die(f"payload exceeds {MAX_PAYLOAD_BYTES // (1024 * 1024)} MiB "
                f"size cap — refusing to install something this size.")
        if len(installed) >= MAX_PAYLOAD_FILES:
            die(f"payload exceeds {MAX_PAYLOAD_FILES}-file cap — refusing "
                f"to install this many files.")
        if dry_run:
            info(f"  {target}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
        installed.append(rel)
    return installed


def write_plasma_env() -> tuple[Path, bool]:
    """Write the plasma-workspace env script. Returns (path, was_new) so the
    caller can tell first-install from upgrade (first install requires a
    full log-out to source QT_PLUGIN_PATH; upgrade just needs plasmashell)."""
    was_new = not PLASMA_ENV_FILE.exists()
    PLASMA_ENV_DIR.mkdir(parents=True, exist_ok=True)
    PLASMA_ENV_FILE.write_text(PLASMA_ENV_CONTENT)
    PLASMA_ENV_FILE.chmod(0o600)
    return PLASMA_ENV_FILE, was_new


def write_manifest(installed: list[Path], extras: list[Path], version: str) -> None:
    """Write MANIFEST. Format: `# version: X.Y.Z` header, then relative
    payload paths, then `@` + absolute path for each extra outside USER_PREFIX."""
    USER_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# version: {version}"]
    lines.extend(str(p) for p in sorted(installed))
    for extra in extras:
        lines.append(f"@{extra}")
    USER_MANIFEST.write_text("\n".join(lines) + "\n")


def remove_orphans(existing_rel: set[str], existing_abs: set[str],
                   new_rel: set[str], new_abs: set[str],
                   *, dry_run: bool) -> int:
    """Delete files the prior install placed that this version no longer ships."""
    removed = 0
    for rel in sorted(existing_rel - new_rel):
        target = safe_rel(rel)
        if not target.exists() and not target.is_symlink():
            continue
        if dry_run:
            info(f"  rm {target}")
        else:
            target.unlink()
        removed += 1
    for abs_path in sorted(existing_abs - new_abs):
        target = safe_extra(abs_path)
        if not target.exists() and not target.is_symlink():
            continue
        if dry_run:
            info(f"  rm {target}")
        else:
            target.unlink()
        removed += 1
    return removed


def refresh_service_cache() -> None:
    if shutil.which("kbuildsycoca6"):
        subprocess.run(["kbuildsycoca6"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("-y", "--yes", action="store_true",
                        help="skip interactive confirmations (install only; "
                             "does not restart plasmashell)")
    parser.add_argument("-r", "--restart-plasmashell", action="store_true",
                        help="on upgrade, restart plasmashell after install")
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would happen without writing files")
    parser.add_argument("--allow-coexist", action="store_true",
                        help="install on top of a system-wide distro package "
                             "(not recommended — Plasma may load the system copy)")
    args = parser.parse_args()

    refuse_if_root()
    validate_home()

    if not PAYLOAD_DIR.is_dir():
        die(f"missing payload: {PAYLOAD_DIR}\n"
            f"run this from the unpacked universal package directory.")

    if not DISTROS_TOML.is_file():
        die(f"missing distros.toml: {DISTROS_TOML}")
    with DISTROS_TOML.open("rb") as fp:
        distros = tomllib.load(fp)

    name, table = detect_distro(distros)
    info(f"Detected: {table.get('display', name)}")

    # Bail before doing anything when a distro package is already installed.
    # We pass `name` so we can suggest the right uninstall command.
    warn_on_system_install(name, allow_coexist=args.allow_coexist)

    if not plasma_present():
        info()
        info("error: Plasma 6 not found (no `plasmashell` on PATH).")
        if "notes" in table:
            info()
            info(table["notes"])
        if "install" in table:
            packages = " ".join(table.get("packages", []))
            cmd = table["install"].format(packages=packages)
            info()
            info("Install the runtime dependencies first:")
            info(f"  {cmd}")
        elif table.get("packages"):
            info()
            info("Your distro isn't in our mapping; install these via your package manager:")
            for pkg in table.get("packages", []):
                info(f"  - {pkg}")
        info()
        return 1

    verify_sha256sums()

    missing_libs = unresolved_dependencies()
    if missing_libs:
        info()
        info("error: AppGrid's bundled plugin can't resolve these libraries on this system:")
        for lib in missing_libs:
            info(f"  - {lib}")
        info()
        if "install" in table:
            packages = " ".join(table.get("packages", []))
            cmd = table["install"].format(packages=packages)
            info("Install the AppGrid runtime dependencies via your package manager:")
            info(f"  {cmd}")
        elif "notes" in table:
            info(table["notes"])
            info()
            info("If you're sure the listed libraries are part of your base image,")
            info("file a bug — our universal package may be linked against versions")
            info("your distro doesn't yet ship.")
        else:
            info("Install the equivalent packages for your distro:")
            for pkg in table.get("packages", []):
                info(f"  - {pkg}")
        info()
        return 1

    new_version = package_version()
    existing = read_existing_manifest()
    new_rel_paths = {str(p.relative_to(PAYLOAD_DIR))
                     for p in PAYLOAD_DIR.rglob("*") if p.is_file()}
    new_abs_paths = {str(PLASMA_ENV_FILE)}

    file_count = len(new_rel_paths)
    info()
    if existing:
        old_version, old_rel, old_abs = existing
        orphans = (old_rel - new_rel_paths) | (old_abs - new_abs_paths)
        info(f"Existing install detected: {describe_transition(old_version, new_version)}")
        info(f"  payload: {file_count} files into {USER_PREFIX}/  (overwrite in place)")
        if orphans:
            info(f"  orphans: {len(orphans)} files from the prior install will be removed")
        info()
        if not confirm("Proceed?", assume_yes=args.yes):
            info("Aborted.")
            return 0
    else:
        info(f"About to install {file_count} files into {USER_PREFIX}/")
        info(f"  version: {new_version}")
        info(f"  source:  {PAYLOAD_DIR}")
        info(f"  target:  {USER_PREFIX}")
        info()
        if not confirm("Proceed?", assume_yes=args.yes):
            info("Aborted.")
            return 0

    if args.dry_run:
        if existing:
            old_version, old_rel, old_abs = existing
            info("[dry-run] would remove orphans:")
            remove_orphans(old_rel, old_abs, new_rel_paths, new_abs_paths, dry_run=True)
        info("[dry-run] would copy:")
        install_payload(dry_run=True)
        return 0

    if existing:
        old_version, old_rel, old_abs = existing
        remove_orphans(old_rel, old_abs, new_rel_paths, new_abs_paths, dry_run=False)

    installed = install_payload(dry_run=False)
    env_script, env_was_new = write_plasma_env()
    write_manifest(installed, extras=[env_script], version=new_version)
    refresh_service_cache()

    info()
    info("Installed.")
    info(f"  Plugin path enabler: {env_script}")
    info()
    if env_was_new:
        info("First install — Plasma needs to re-read its session environment to")
        info("pick up the new Qt plugin path. Log out and log back in, then")
        info("plasmashell can load the .so.")
        info("(A plain `kquitapp6 plasmashell && kstart plasmashell` doesn't reload")
        info("the session env, so the full log-out cycle is what matters the first time.)")
    else:
        info("Upgrade — the session already has QT_PLUGIN_PATH set from the prior")
        info("install. Plasmashell still needs to restart so it drops the old .so")
        info("from memory and loads the new one.")
        info()
        # -y deliberately does NOT restart (unattended = non-destructive);
        # only -r asks for the restart explicitly.
        if args.restart_plasmashell:
            should_restart = True
        elif args.yes:
            should_restart = False
        else:
            should_restart = confirm("Restart plasmashell now?", assume_yes=False)
        if should_restart:
            info("Restarting plasmashell...")
            subprocess.run(["kquitapp6", "plasmashell"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=False)
            subprocess.Popen(["kstart", "plasmashell"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            info("Done.")
        else:
            info("Restart manually when convenient:")
            info("  kquitapp6 plasmashell && kstart plasmashell")
    info()
    info("To uninstall later, run:")
    info(f"  {SCRIPT_DIR / 'uninstall.sh'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
