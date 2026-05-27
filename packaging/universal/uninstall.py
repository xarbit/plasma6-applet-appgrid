#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Removes the files installed by install.py from ~/.local/, reading the
manifest written there at install time. Refuses to delete anything not
listed in the manifest — the universal package only ever cleans up what
it placed itself.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

USER_PREFIX = Path.home() / ".local"
USER_MANIFEST = USER_PREFIX / "share" / "appgrid" / "MANIFEST"

PLASMA_ENV_FILE = (Path.home() / ".config" / "plasma-workspace" / "env"
                   / "appgrid-user-local.sh")
ALLOWED_ABS_EXTRAS = frozenset({PLASMA_ENV_FILE})

# Dirs pruned (only if empty) after removing files. Hardcoded so we never
# recurse the whole ~/.local tree.
PRUNE_CANDIDATES = (
    USER_PREFIX / "share" / "plasma" / "plasmoids" / "dev.xarbit.appgrid",
    USER_PREFIX / "share" / "plasma" / "plasmoids" / "dev.xarbit.appgrid.panel",
    USER_PREFIX / "share" / "appgrid",
)


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
        die("refusing to uninstall as root — the universal package lives "
            "under the invoking user's ~/.local/. Run as your normal user.")


def validate_home() -> None:
    home = Path.home()
    if not home.is_absolute() or home == Path("/") or str(home) == "":
        die(f"refusing to uninstall: $HOME ({home}) is not a sane user "
            f"directory.")


def safe_rel(rel: str) -> Path:
    """Reject `..` traversal and resolve under USER_PREFIX."""
    if any(part == ".." for part in Path(rel).parts) or Path(rel).is_absolute():
        die(f"MANIFEST entry has an unsafe relative path: {rel!r}")
    candidate = (USER_PREFIX / rel).resolve()
    base = USER_PREFIX.resolve()
    try:
        candidate.relative_to(base)
    except ValueError:
        die(f"MANIFEST entry escapes USER_PREFIX: {rel!r} -> {candidate}")
    return candidate


def safe_extra(abs_path: str) -> Path:
    """Reject absolute paths not in ALLOWED_ABS_EXTRAS."""
    candidate = Path(abs_path).resolve()
    if candidate not in {p.resolve() for p in ALLOWED_ABS_EXTRAS}:
        die(f"refusing to remove path outside the allowlist: {abs_path}")
    return candidate


def prune_empty_dirs() -> None:
    for root in PRUNE_CANDIDATES:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*"), reverse=True):
            if path.is_dir() and not any(path.iterdir()):
                path.rmdir()
        if root.is_dir() and not any(root.iterdir()):
            root.rmdir()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("-y", "--yes", action="store_true",
                        help="skip interactive confirmation")
    parser.add_argument("--dry-run", action="store_true",
                        help="print what would happen without removing files")
    args = parser.parse_args()

    refuse_if_root()
    validate_home()

    if not USER_MANIFEST.is_file():
        die(f"no AppGrid manifest at {USER_MANIFEST}\n"
            f"either it was never installed via this package, or the manifest was removed.")

    # MANIFEST line shapes:
    #   `# version: X.Y.Z` — informational header
    #   `share/foo/bar`    — relative to USER_PREFIX
    #   `@/abs/path`       — absolute, must be in ALLOWED_ABS_EXTRAS
    installed_version = "unknown"
    rel_entries: list[str] = []
    abs_entries: list[str] = []
    for raw in USER_MANIFEST.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# version:"):
                installed_version = line.split(":", 1)[1].strip() or "unknown"
            continue
        if line.startswith("@"):
            entry = line[1:]
            safe_extra(entry)
            abs_entries.append(entry)
        else:
            safe_rel(line)
            rel_entries.append(line)

    total = len(rel_entries) + len(abs_entries)
    info(f"Found AppGrid universal install (version: {installed_version})")
    info(f"About to remove {total} files (including {len(abs_entries)} extras outside {USER_PREFIX})")
    if not confirm("Proceed?", assume_yes=args.yes):
        info("Aborted.")
        return 0

    for rel in rel_entries:
        target = safe_rel(rel)
        if not target.exists() and not target.is_symlink():
            continue
        if args.dry_run:
            info(f"  rm {target}")
        else:
            target.unlink()
    for abs_path in abs_entries:
        target = safe_extra(abs_path)
        if not target.exists() and not target.is_symlink():
            continue
        if args.dry_run:
            info(f"  rm {target}")
        else:
            target.unlink()

    if not args.dry_run:
        USER_MANIFEST.unlink(missing_ok=True)
        prune_empty_dirs()
        if shutil.which("kbuildsycoca6"):
            subprocess.run(["kbuildsycoca6"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)

    info("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
