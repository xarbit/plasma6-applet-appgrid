#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Thin wrapper around install.py. Verifies Python 3.11+ is available
# (we use tomllib from the stdlib, introduced in 3.11) and forwards
# every argument to install.py. The wrapper exists so users get a clear
# message instead of a cryptic ModuleNotFoundError when Python is too old.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    cat >&2 <<EOF
error: Python 3.11+ is required but \`python3\` was not found.

Install it via your package manager, then re-run:
  arch:    sudo pacman -S python
  fedora:  sudo dnf install python3
  debian:  sudo apt install python3
  suse:    sudo zypper install python3
EOF
    exit 1
fi

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    cat >&2 <<EOF
error: Python 3.11+ is required (we use the tomllib standard-library module).
       Detected: $(python3 -V 2>&1)
EOF
    exit 1
fi

exec python3 "$SCRIPT_DIR/install.py" "$@"
