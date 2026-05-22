/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Kirigami.Icon with an optional soft drop shadow, toggled by the
    iconShadow setting.

    Shadow on:  the icon is a texture source for a MultiEffect, which is
                the visible item — callers animate or grab this whole
                ShadowedIcon, not the inner icon.
    Shadow off: the MultiEffect is never created and the icon draws
                itself directly — no per-icon offscreen render pass.
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

    readonly property bool _shadowEnabled: Plasmoid.configuration.iconShadow

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        visible: !root._shadowEnabled
    }

    Loader {
        anchors.fill: icon
        active: root._shadowEnabled
        sourceComponent: MultiEffect {
            source: icon
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 0.45
            shadowVerticalOffset: 2
            shadowOpacity: 0.2
        }
    }
}
