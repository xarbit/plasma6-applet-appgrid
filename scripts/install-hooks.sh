#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Point git at the in-repo .githooks/ directory so the pre-commit and
# pre-push gates run on every commit/push. One-shot: survives clone +
# pull because the hooks are versioned in the repo.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config core.hooksPath .githooks

echo "git hooks path -> .githooks"
echo "active hooks:"
for h in .githooks/*; do
    [ -f "$h" ] && [ -x "$h" ] && printf '  %s\n' "$(basename "$h")"
done
echo
echo "skip a single run with: git commit --no-verify  /  git push --no-verify"
