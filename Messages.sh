#!/bin/sh
# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

# Extract translatable strings for KDE i18n.

XGETTEXT_FLAGS="--from-code=UTF-8 -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 \
    -ki18ncp:1c,2,3 -ktr2i18n:1 -kI18N_NOOP:1 -kI18N_NOOP2:1c,2 \
    -kaliasLocale -kki18n:1 -kki18nc:1c,2 -kki18np:1,2 -kki18ncp:1c,2,3"

PODIR="${podir:-po}"
BUGADDR="https://github.com/xarbit/appgrid/issues"

# QML files
find package/contents/ui -name '*.qml' | sort > "${PODIR}/qmlfiles.list"
xgettext ${XGETTEXT_FLAGS} --msgid-bugs-address="${BUGADDR}" \
    --files-from="${PODIR}/qmlfiles.list" \
    -D "${PWD}" -o "${PODIR}/dev.xarbit.appgrid.pot"
rm -f "${PODIR}/qmlfiles.list"
