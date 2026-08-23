#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# One-line install for the AppGrid Universal Package:
#
#   curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/xarbit/plasma6-applet-appgrid/refs/heads/main/universal_install.sh && bash universal_install.sh
#
# This does exactly the manual steps from the docs
# (https://appgrid.xarbit.dev/#universal-install) 
#
# After a successful install, this script copies itself to
# ~/.local/bin/appgrid-update. From then on, updating is just:
#   appgrid-update
# 

set -euo pipefail

REPO="xarbit/plasma6-applet-appgrid"
UPDATER="${HOME}/.local/bin/appgrid-update"
SELF_URL="https://raw.githubusercontent.com/xarbit/plasma6-applet-appgrid/refs/heads/main/universal_install.sh"

SELF_FILE=""
if [ -f "$0" ]; then
    SELF_FILE="$(cd "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
fi

# --- detect architecture -----------------------------------------------
case "$(uname -m)" in
    x86_64|amd64)  ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) echo "error: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# --- resolve latest version (follow the /releases/latest redirect) -----
VERSION="$(curl -sSf -o /dev/null -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest" | sed 's#.*/tag/##')"
[ -n "${VERSION}" ] || { echo "error: could not resolve latest AppGrid version" >&2; exit 1; }

NAME="appgrid-universal-${VERSION#v}-${ARCH}"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

echo "Installing AppGrid ${VERSION} (${ARCH})"

# --- download, verify, extract, install (the same 4 steps as the docs) -
cd "${TMPDIR:-/tmp}"

curl -LO "${BASE_URL}/${NAME}.tar.gz"
curl -LO "${BASE_URL}/${NAME}.tar.gz.sha256"
sha256sum -c "${NAME}.tar.gz.sha256"

tar -xzf "${NAME}.tar.gz"
cd "${NAME}"
./install.sh "$@"

# Copy to .local/bin/appgrid-update
mkdir -p "${HOME}/.local/bin"

if [ -n "${SELF_FILE}" ]; then
    cp "${SELF_FILE}" "${UPDATER}"
else
    # Piped via `curl ... | sh` -- no local file exists to cp, so fetch
    # the canonical copy once instead.
    curl -fsSL "${SELF_URL}" -o "${UPDATER}"
fi

chmod +x "${UPDATER}"

echo "Installed updater to ${UPDATER} -- run 'appgrid-update' any time to update."
 
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) echo "Note: ${HOME}/.local/bin is not on your PATH; run it as ${UPDATER} or add it to PATH." ;;
esac
