#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds the universal package tarball:
#   appgrid-universal-<version>-<arch>.tar.gz
#
# Run from the project root with a built tree present (cmake -B build ...).
# CI uses this; locally you can run it after a full build to sanity-check.
#
# Usage:
#   packages/universal/build-package.sh <version> <arch> <build-dir> <out-dir>

set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <version> <arch> <build-dir> <out-dir>" >&2
    exit 2
fi

VERSION="$1"
ARCH="$2"
BUILD_DIR="$3"
OUT_DIR="$4"

# Resolve to absolute paths so we can cd around freely later.
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_NAME="appgrid-universal-${VERSION}-${ARCH}"
STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

PKG_ROOT="$STAGE_DIR/$PKG_NAME"
PAYLOAD_ROOT="$PKG_ROOT/files"

mkdir -p "$PKG_ROOT" "$PAYLOAD_ROOT"

# Install the build tree into the payload, using /.local as the prefix so the
# resulting tree maps cleanly under the user's ~/.local on extract.
DESTDIR="$PAYLOAD_ROOT/__prefix__" \
    cmake --install "$BUILD_DIR" --prefix "/.local"

# Move the install tree out of the prefix wrapper to land at $PAYLOAD_ROOT
# (so SCRIPT_DIR/files/lib/... matches ~/.local/lib/...).
mv "$PAYLOAD_ROOT/__prefix__/.local/"* "$PAYLOAD_ROOT/"
rm -rf "$PAYLOAD_ROOT/__prefix__"

# Bundle the installer scripts + dep declarations next to the payload.
cp "$PROJECT_ROOT/packages/universal/install.sh"   "$PKG_ROOT/"
cp "$PROJECT_ROOT/packages/universal/install.py"   "$PKG_ROOT/"
cp "$PROJECT_ROOT/packages/universal/uninstall.sh" "$PKG_ROOT/"
cp "$PROJECT_ROOT/packages/universal/uninstall.py" "$PKG_ROOT/"
cp "$PROJECT_ROOT/packages/universal/distros.toml" "$PKG_ROOT/"
cp "$PROJECT_ROOT/packages/universal/INSTALL.TXT"  "$PKG_ROOT/"
chmod +x "$PKG_ROOT/install.sh" "$PKG_ROOT/install.py" \
         "$PKG_ROOT/uninstall.sh" "$PKG_ROOT/uninstall.py"

# Version stamp — install.py reads this to detect upgrade / downgrade /
# reinstall of an existing user-local install.
echo "$VERSION" > "$PKG_ROOT/VERSION"

# Per-package README explaining what's in this tarball.
cat > "$PKG_ROOT/README.md" <<EOF
# AppGrid universal package — $VERSION ($ARCH)

Drop-in package for immutable distros (KDE Linux / Banana) and anyone who
prefers a user-local install over a system package.

See [\`INSTALL.TXT\`](./INSTALL.TXT) for the full step-by-step guide,
upgrade/uninstall notes, and troubleshooting.

## Install

\`\`\`
./install.sh
\`\`\`

Files land in \`~/.local/\`. Plasma loads them alongside system plasmoids;
no sudo required. The installer prints the per-distro command for any
missing runtime dependencies — it never installs OS packages itself.

Requires Python 3.11+ (uses the stdlib \`tomllib\` module to read
\`distros.toml\`). \`install.sh\` is a thin wrapper that gates on the
Python version; the real work lives in \`install.py\`.

## Uninstall

\`\`\`
./uninstall.sh
\`\`\`

Reads \`~/.local/share/appgrid/MANIFEST\` (written at install time) and
removes only the files it placed there.

## What's inside

- \`files/\` — the install payload (mirrors \`~/.local/\` layout)
- \`install.sh\` / \`uninstall.sh\` — Python-version-gated wrappers
- \`install.py\` / \`uninstall.py\` — the actual installer / uninstaller
- \`distros.toml\` — per-distro dependency declarations
- \`INSTALL.TXT\` — full installation guide (steps, upgrade,
  troubleshooting)
- \`MANIFEST\` — list of payload files
- \`SHA256SUMS\` — checksums of the payload, verified by install.py
- \`VERSION\` — version string baked at build time (read by install.py to
  detect upgrade vs. reinstall vs. downgrade of an existing install)
EOF

# Manifest of payload files (used by uninstall.sh too, written at install time).
( cd "$PAYLOAD_ROOT" && find . -type f -printf "%P\n" | sort ) > "$PKG_ROOT/MANIFEST"

# Integrity checksums over the payload (install.sh verifies these).
( cd "$PKG_ROOT" && \
    find files -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )

# Final tarball.
TARBALL="$OUT_DIR/${PKG_NAME}.tar.gz"
( cd "$STAGE_DIR" && tar -czf "$TARBALL" "$PKG_NAME" )

# SHA256 of the tarball itself, for release-page integrity.
( cd "$OUT_DIR" && sha256sum "${PKG_NAME}.tar.gz" > "${PKG_NAME}.tar.gz.sha256" )

echo "Built: $TARBALL"
echo "       $(cat "$OUT_DIR/${PKG_NAME}.tar.gz.sha256")"
