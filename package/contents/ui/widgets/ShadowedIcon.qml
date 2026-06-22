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

    // var, not string: KRunner results hand us a QIcon (Qt::DecorationRole)
    // rather than an icon-name string, and Kirigami.Icon.source takes either.
    property var source: ""
    property alias active: icon.active

    required property bool shadowEnabled

    // Bumped (e.g. on a system icon-theme change) to force a reload: the icon
    // name is unchanged, so Kirigami.Icon won't re-resolve on its own. We clear
    // and rebind the source to make it (and the shadow's MultiEffect texture)
    // re-render with the new theme. See AppFilterModel.iconGeneration.
    property int reloadToken: 0
    onReloadTokenChanged: refresh()

    // Force the icon (and the shadow's MultiEffect texture) to re-resolve: clear
    // then rebind the source. The icon name is unchanged on a theme switch, so
    // Kirigami.Icon won't re-resolve on its own (reloadToken bumps this).
    function refresh() {
        icon.source = ""
        icon.source = Qt.binding(() => root.source)
    }

    implicitWidth: icon.implicitWidth
    implicitHeight: icon.implicitHeight

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: root.source
        // Show the plain icon until the (async) shadow pass is ready, so a row
        // scrolling in is never blank while the MultiEffect builds off-frame.
        visible: !root.shadowEnabled || shadowLoader.status !== Loader.Ready
    }

    Loader {
        id: shadowLoader
        anchors.fill: icon
        active: root.shadowEnabled
        // Build the offscreen shadow pass off the scroll frame — it is the heavy
        // part of the delegate, so deferring it keeps scrolling smooth.
        asynchronous: true
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
