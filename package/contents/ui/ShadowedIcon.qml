/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Kirigami.Icon with an optional soft drop shadow, toggled by the
    iconShadow setting. The icon is rendered through a MultiEffect, so
    callers animate or grab this whole item for a drag preview — not the
    inner Kirigami.Icon, which is only a texture source.
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: root

    property alias source: icon.source
    property alias active: icon.active

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        visible: false
    }

    MultiEffect {
        anchors.fill: icon
        source: icon
        shadowEnabled: Plasmoid.configuration.iconShadow
        shadowColor: "#000000"
        shadowBlur: 0.45
        shadowVerticalOffset: 2
        shadowOpacity: 0.2
    }
}
