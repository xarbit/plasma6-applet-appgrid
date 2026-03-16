#!/bin/sh
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Translation String Extraction Script
# =====================================
#
# This script extracts all translatable strings from QML and C++ source files
# into a .pot (Portable Object Template) file. The .pot file serves as the
# master template from which per-language .po files are created and updated.
#
# How the translation pipeline works:
#
#   1. Run this script        -> generates/updates  po/dev.xarbit.appgrid.pot
#   2. msgmerge per language   -> updates each       po/<lang>/dev.xarbit.appgrid.po
#   3. Translators fill in msgstr entries in the .po files
#   4. CMake (ki18n_install)   -> compiles .po to    .mo files at build time
#   5. At runtime, KDE's i18n  -> loads .mo files from /usr/share/locale/
#
# Usage:
#   cd <project-root>
#   bash Messages.sh                          # extract strings into .pot
#   msgmerge --update po/de/dev.xarbit.appgrid.po po/dev.xarbit.appgrid.pot  # update German
#
# Notes:
#   - QML files use i18nd("dev.xarbit.appgrid", "string") for explicit domain lookup
#   - C++ files use i18nd("dev.xarbit.appgrid", "string") from KLocalizedString
#   - The -k flags below tell xgettext which function signatures to scan for

# xgettext flags for KDE i18n function signatures:
#   -ki18n:1        -> i18n("string")               (1st arg is the message)
#   -ki18nc:1c,2    -> i18nc("context", "string")   (1st is context, 2nd is message)
#   -ki18np:1,2     -> i18np("singular", "plural")
#   -ki18nd:2       -> i18nd("domain", "string")    (2nd arg is the message)
#   -ki18ndc:2c,3   -> i18ndc("domain", "context", "string")
XGETTEXT_FLAGS="--from-code=UTF-8 -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 \
    -ki18ncp:1c,2,3 -ktr2i18n:1 -kI18N_NOOP:1 -kI18N_NOOP2:1c,2 \
    -kaliasLocale -kki18n:1 -kki18nc:1c,2 -kki18np:1,2 -kki18ncp:1c,2,3"

# Output directory for .pot and temp files (defaults to "po")
PODIR="${podir:-po}"

# Bug report URL included in the .pot header
BUGADDR="https://github.com/xarbit/plasma6-applet-appgrid/issues"

# Collect all translatable source files (QML + C++) into a temp list
{ find package/contents/ui -name '*.qml'; find src -name '*.cpp'; } | sort > "${PODIR}/sourcefiles.list"

# Run xgettext to extract strings into the .pot template
# Additional -k flags for domain-aware i18nd/i18ndc variants used in this project
xgettext ${XGETTEXT_FLAGS} --msgid-bugs-address="${BUGADDR}" \
    -ki18nd:2 -ki18ndc:2c,3 -ki18ndp:2,3 \
    --files-from="${PODIR}/sourcefiles.list" \
    -D "${PWD}" -o "${PODIR}/dev.xarbit.appgrid.pot"

# Clean up temp file
rm -f "${PODIR}/sourcefiles.list"
