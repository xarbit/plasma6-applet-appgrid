/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The drag-to-folder marker icon (#200): shown in place of a target's icon once
    a spring-loaded fold arms, popping once to confirm. Shared by the app-icon
    (folder-new) and folder-tile (+) fold targets so the cue is identical. The
    caller sets source / size / visible; centring + the pop live here.
*/

import QtQuick

import org.kde.kirigami as Kirigami

Kirigami.Icon {
    id: marker

    // Peak scale of the confirm pop.
    readonly property real _popScale: 1.25

    anchors.centerIn: parent
    color: Kirigami.Theme.highlightColor

    // One pop each time the marker appears (the fold arms), not a loop.
    onVisibleChanged: if (visible) pop.restart()
    SequentialAnimation {
        id: pop
        NumberAnimation {
            target: marker
            property: "scale"
            from: 1.0
            to: marker._popScale
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: marker
            property: "scale"
            from: marker._popScale
            to: 1.0
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutBack
        }
    }
}
