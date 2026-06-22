/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma's standard "new app" badge (Kirigami.Badge, KDE Frameworks 6.25+).
    Loaded behind a Loader in AppIconDelegate so older Plasma 6 — whose Kirigami
    has no Badge type — fails that Loader cleanly and falls back to a plain dot.
    The delegate already announces "new" to a screen reader, so the badge is
    decorative here.
*/

import QtQuick

import org.kde.kirigami as Kirigami

Kirigami.Badge {
    // Size-preset multiplier (Scale.textScale) from the delegate, so the badge
    // tracks the configured size like the labels do.
    property real fontScale: 1

    text: i18nd("dev.xarbit.appgrid", "New")
    type: Kirigami.Badge.Type.Positive
    font.pointSize: Kirigami.Theme.smallFont.pointSize * fontScale
    Accessible.ignored: true
}
