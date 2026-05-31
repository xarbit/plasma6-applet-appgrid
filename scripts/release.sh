#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# release.sh <version>
#
# One-shot local release dance. Bumps every hardcoded version site,
# regenerates CHANGELOG.md, drops a placeholder <release> entry in
# the AppStream metainfo, then creates the commit + annotated tag.
# Push is intentionally NOT automated — the script prints the exact
# command and stops so you can review the diff and back out cheaply.
#
# Templated version sites (metadata*.json.in, packaging/aur/PKGBUILD*.in,
# packaging/rpm/appgrid.spec.in, packaging/universal/build-package.sh)
# pull from CMakeLists.txt / CI env at build time and need no bump here.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

usage() {
    cat <<EOF
usage: $0 <version>
   e.g. $0 1.9.0      stable
        $0 1.9.0-rc.1 release candidate
EOF
    exit 1
}

VER="${1:-}"
[ -z "$VER" ] && usage
# Loose semver gate — accepts X.Y.Z and X.Y.Z-rc.N / -beta.N etc.
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
    echo "error: '$VER' is not a valid semver tag" >&2
    exit 1
fi

TAG="v$VER"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi

if ! git diff --quiet HEAD -- .; then
    echo "error: working tree dirty — commit or stash first" >&2
    git status --short
    exit 1
fi

echo "=== release v$VER ==="

# --- 1. CMakeLists.txt: project(AppGrid VERSION X.Y.Z) ---
# Strip any -rc.N suffix because CMake's project(... VERSION) wants pure
# numerics; the tag carries the suffix instead.
CMAKE_VER="${VER%%-*}"
sed -i -E "s/project\(AppGrid VERSION [0-9.]+ /project(AppGrid VERSION $CMAKE_VER /" CMakeLists.txt
echo "  CMakeLists.txt    -> project(AppGrid VERSION $CMAKE_VER)"

# --- 2. PKGBUILD: pkgver=X.Y.Z + reset pkgrel ---
sed -i -E "s/^pkgver=.*/pkgver=$CMAKE_VER/" PKGBUILD
sed -i -E "s/^pkgrel=.*/pkgrel=1/"          PKGBUILD
echo "  PKGBUILD          -> pkgver=$CMAKE_VER pkgrel=1"

# --- 3. AppStream metainfo: insert new <release> at top of <releases> ---
TODAY="$(date -u +%Y-%m-%d)"
if grep -q "<release version=\"$VER\"" dev.xarbit.appgrid.metainfo.xml; then
    echo "  metainfo          -> release entry already exists, skipping"
else
    python3 - "$VER" "$TODAY" <<'PY'
import sys, re, pathlib
ver, date = sys.argv[1], sys.argv[2]
p = pathlib.Path("dev.xarbit.appgrid.metainfo.xml")
src = p.read_text()
new = f'''        <release version="{ver}" date="{date}">
            <description>
                <p>See CHANGELOG.md for the full list of changes.</p>
            </description>
        </release>
'''
patched, n = re.subn(r"(    <releases>\n)", r"\1" + new, src, count=1)
if n != 1:
    sys.exit("metainfo: <releases> opening tag not found")
p.write_text(patched)
PY
    echo "  metainfo          -> + <release version=\"$VER\" date=\"$TODAY\"/>"
fi

# --- 4. Regenerate CHANGELOG.md ---
./scripts/changelog.sh >/dev/null
echo "  CHANGELOG.md      -> regenerated"

# --- 5. Review gate ---
echo
echo "=== diff ==="
git --no-pager diff --stat -- CMakeLists.txt PKGBUILD dev.xarbit.appgrid.metainfo.xml CHANGELOG.md

echo
read -r -p "commit + tag $TAG? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] || { echo "aborted — files left modified for review"; exit 1; }

# --- 6. Commit + tag ---
git add CMakeLists.txt PKGBUILD dev.xarbit.appgrid.metainfo.xml CHANGELOG.md
git commit -m "chore: release $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo
echo "tagged $TAG. push with:"
echo "  git push origin $(git rev-parse --abbrev-ref HEAD) --follow-tags"
echo
echo "release.yml will pick up the tag push and build the universal packages."
