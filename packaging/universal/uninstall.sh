#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Thin wrapper around uninstall.py. Mirror of install.sh — verifies
# Python 3.11+ then forwards every argument to uninstall.py.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: Python 3.11+ is required but \`python3\` was not found." >&2
    exit 1
fi

if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    echo "error: Python 3.11+ is required. Detected: $(python3 -V 2>&1)" >&2
    exit 1
fi

exec python3 "$SCRIPT_DIR/uninstall.py" "$@"
