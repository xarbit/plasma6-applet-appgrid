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

# Qt's default plugin search path is baked at Qt build time to /usr/lib/qt6/
# plugins; without help it never looks under ~/.local/. plasma-workspace
# sources every *.sh in this directory at session start, so dropping a tiny
# script here adds our plugin dir to QT_PLUGIN_PATH for the whole session.
PLASMA_ENV_DIR = Path.home() / ".config" / "plasma-workspace" / "env"
PLASMA_ENV_FILE = PLASMA_ENV_DIR / "appgrid-user-local.sh"
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

    Checks VARIANT_ID first so atomic variants (Kinoite, Silverblue, etc.)
    take precedence over their base distro (Fedora), then ID, then ID_LIKE.
    """
    os_release = parse_os_release()
    variant = os_release.get("VARIANT_ID", "").strip().lower()
    primary = [os_release.get("ID", "").strip().lower()]
    likes = [s.strip().lower() for s in os_release.get("ID_LIKE", "").split() if s.strip()]

    # Variant matches first (atomic variant beats its base distro).
    if variant:
        for name, table in distros.items():
            if variant in table.get("aliases", []):
                return name, table

    # Then ID, then ID_LIKE fallbacks.
    for ids in (primary, likes):
        for name, table in distros.items():
            for alias in table.get("aliases", []):
                if alias in ids:
                    return name, table

    return "generic", distros.get("generic", {})


# -- Runtime checks --------------------------------------------------------

def plasma_present() -> bool:
    """Whether Plasma 6 looks usable on this system.

    We probe for the `plasmashell` binary on PATH. It's the Plasma session
    process and ships with every Plasma install; if it's missing, our
    plasmoid has nothing to load into. The Plasma install location doesn't
    matter — we install to ~/.local/ regardless, and Plasma auto-discovers
    user-local plasmoids alongside system ones.
    """
    return shutil.which("plasmashell") is not None


def unresolved_dependencies() -> list[str]:
    """Run `ldd` on the bundled .so files and return any libraries the
    dynamic linker can't resolve. Empty list means everything is satisfied.

    Catches the case where Plasma is installed (plasmashell on PATH) but
    a specific library AppGrid links against is missing — e.g. an older
    distro without `libPlasmaActivities` packaged separately.
    """
    if not shutil.which("ldd"):
        return []  # can't probe; let install proceed and fail loudly later

    missing: set[str] = set()
    for so in PAYLOAD_DIR.rglob("*.so"):
        try:
            out = subprocess.run(["ldd", str(so)], capture_output=True,
                                 text=True, check=False).stdout
        except OSError:
            continue
        for line in out.splitlines():
            # ldd line format: "\tlibFoo.so.6 => not found"
            line = line.strip()
            if "=> not found" in line:
                lib = line.split("=>")[0].strip()
                if lib:
                    missing.add(lib)
    return sorted(missing)


# -- Existing-install detection --------------------------------------------

def package_version() -> str:
    """Version baked into this package (written by build-package.sh)."""
    if VERSION_FILE.is_file():
        return VERSION_FILE.read_text().strip() or "unknown"
    return "unknown"


def read_existing_manifest() -> tuple[str, set[str], set[str]] | None:
    """Returns (installed_version, rel_paths, abs_paths) or None if no prior install."""
    if not USER_MANIFEST.is_file():
        return None
    version = "unknown"
    rel: set[str] = set()
    abs_: set[str] = set()
    for line in USER_MANIFEST.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# version:"):
                version = line.split(":", 1)[1].strip() or "unknown"
            continue
        if line.startswith("@"):
            abs_.add(line[1:])
        else:
            rel.add(line)
    return version, rel, abs_


def version_tuple(v: str) -> tuple[int, ...]:
    """Lenient numeric tuple — strips leading 'v', non-numeric tail; for ordering only."""
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


# -- Integrity check -------------------------------------------------------

def verify_sha256sums() -> bool:
    """Verify SHA256SUMS in SCRIPT_DIR against the payload files."""
    if not SHA256SUMS_FILE.is_file():
        info("Note: no SHA256SUMS file in this package; skipping integrity check.")
        return True
    for line in SHA256SUMS_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # `sha256sum` output: "<hex>  <path>" (two spaces, path relative to SCRIPT_DIR)
        try:
            expected, rel = line.split(None, 1)
        except ValueError:
            die(f"malformed SHA256SUMS entry: {line!r}")
        target = SCRIPT_DIR / rel
        if not target.is_file():
            die(f"missing payload file: {rel}")
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != expected:
            die(f"SHA256 mismatch for {rel}\n  expected: {expected}\n  actual:   {digest}")
    return True


# -- Install ---------------------------------------------------------------

def install_payload(*, dry_run: bool) -> list[Path]:
    """Copy PAYLOAD_DIR/* into USER_PREFIX/*. Returns the list of relative paths."""
    installed: list[Path] = []
    for src in PAYLOAD_DIR.rglob("*"):
        if not src.is_file():
            continue
        rel = src.relative_to(PAYLOAD_DIR)
        target = USER_PREFIX / rel
        if dry_run:
            info(f"  {target}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
        installed.append(rel)
    return installed


def write_plasma_env() -> tuple[Path, bool]:
    """Drop the plasma-workspace env script so QT_PLUGIN_PATH includes ~/.local.

    Returns (path, was_new). was_new is True only on first install — on
    upgrade/reinstall the script is already in place and the running session
    already has QT_PLUGIN_PATH set, so plasmashell can just be restarted
    without a full log-out.
    """
    was_new = not PLASMA_ENV_FILE.exists()
    PLASMA_ENV_DIR.mkdir(parents=True, exist_ok=True)
    PLASMA_ENV_FILE.write_text(PLASMA_ENV_CONTENT)
    PLASMA_ENV_FILE.chmod(0o755)
    return PLASMA_ENV_FILE, was_new


def write_manifest(installed: list[Path], extras: list[Path], version: str) -> None:
    """Record installed paths.

    `installed` is the payload (relative to USER_PREFIX so uninstall can
    rebuild absolute paths). `extras` are absolute paths to files we placed
    outside USER_PREFIX (e.g. the plasma-workspace env script) and need to
    track separately, since the manifest's primary semantic is "relative to
    USER_PREFIX".

    The leading `# version:` header lets a later install detect upgrade vs.
    reinstall vs. downgrade without consulting any other state.
    """
    USER_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# version: {version}"]
    lines.extend(str(p) for p in sorted(installed))
    for extra in extras:
        # Tag absolute paths so uninstall.py can tell them apart on read.
        lines.append(f"@{extra}")
    USER_MANIFEST.write_text("\n".join(lines) + "\n")


def remove_orphans(existing_rel: set[str], existing_abs: set[str],
                   new_rel: set[str], new_abs: set[str],
                   *, dry_run: bool) -> int:
    """Delete files the prior install placed that this version no longer ships.

    Same-path overwrites are handled by copy2 / write_text later; only the
    set difference needs explicit removal. Returns the count removed.
    """
    removed = 0
    for rel in sorted(existing_rel - new_rel):
        target = USER_PREFIX / rel
        if not target.exists() and not target.is_symlink():
            continue
        if dry_run:
            info(f"  rm {target}")
        else:
            target.unlink()
        removed += 1
    for abs_path in sorted(existing_abs - new_abs):
        target = Path(abs_path)
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


# -- Main ------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("-y", "--yes", action="store_true",
                        help="skip interactive confirmations (install only; "
                             "does not restart plasmashell)")
    parser.add_argument("-r", "--restart-plasmashell", action="store_true",
                        help="on upgrade, restart plasmashell after install")
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would happen without writing files")
    args = parser.parse_args()

    if not PAYLOAD_DIR.is_dir():
        die(f"missing payload: {PAYLOAD_DIR}\n"
            f"run this from the unpacked universal package directory.")

    if not DISTROS_TOML.is_file():
        die(f"missing distros.toml: {DISTROS_TOML}")
    with DISTROS_TOML.open("rb") as fp:
        distros = tomllib.load(fp)

    name, table = detect_distro(distros)
    info(f"Detected: {table.get('display', name)}")

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
        # Restart only when explicitly requested via -r/--restart-plasmashell.
        # -y alone deliberately does NOT restart (unattended runs stay
        # non-destructive). Interactive runs without -y prompt the user;
        # default no, since restarting plasmashell blanks the panel briefly
        # and closes any open AppGrid popup.
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
