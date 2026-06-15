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

Item {
    id: root

    property string source: ""
    property alias active: icon.active

    required property bool shadowEnabled

    // Bumped (e.g. on a system icon-theme change) to force a reload: the icon
    // name is unchanged, so Kirigami.Icon won't re-resolve on its own. We clear
    // and rebind the source to make it (and the shadow's MultiEffect texture)
    // re-render with the new theme. See AppFilterModel.iconGeneration.
    property int reloadToken: 0
    onReloadTokenChanged: {
        icon.source = ""
        icon.source = Qt.binding(() => root.source)
    }

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: root.source
        visible: !root.shadowEnabled
    }

    Loader {
        anchors.fill: icon
        active: root.shadowEnabled
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
