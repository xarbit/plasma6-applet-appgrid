/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property Item target: null
    property bool effectsBeforeAnimation: false
    signal openFinished()
    signal closeFinished()

    // Offset to place the panel's bottom edge at the very bottom of the screen
    readonly property real bottomOffset: target && target.parent
        ? target.parent.height * 0.5
        : 500

    function open() {
        target.transformOrigin = Item.Bottom
        openAnim.start()
    }
    function close() {
        target.transformOrigin = Item.Bottom
        closeAnim.start()
    }
    function reset() {}

    // Open: panel grows from the bottom of the screen upward to center
    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            // Rise from bottom edge to center
            NumberAnimation {
                target: root.target; property: "anchors.verticalCenterOffset"
                from: root.bottomOffset; to: 0
                duration: Kirigami.Units.longDuration * 1.2
                easing.type: Easing.OutCubic
            }
            // Grow from nothing to exact final size
            NumberAnimation {
                target: root.target; property: "scale"
                from: 0.0; to: 1.0
                duration: Kirigami.Units.longDuration * 1.2
                easing.type: Easing.OutCubic
            }
            // Quick fade in
            NumberAnimation {
                target: root.target; property: "opacity"
                from: 0.0; to: 1.0
                duration: Kirigami.Units.longDuration * 0.4
                easing.type: Easing.OutQuad
            }
        }
        onFinished: root.openFinished()
    }

    // Close: shrink back down to bottom of screen
    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            // Sink to very bottom of screen
            NumberAnimation {
                target: root.target; property: "anchors.verticalCenterOffset"
                from: 0; to: root.bottomOffset
                duration: Kirigami.Units.shortDuration * 1.5
                easing.type: Easing.InCubic
            }
            // Shrink to nothing
            NumberAnimation {
                target: root.target; property: "scale"
                from: 1.0; to: 0.0
                duration: Kirigami.Units.shortDuration * 1.5
                easing.type: Easing.InCubic
            }
            // Fade out near the end
            NumberAnimation {
                target: root.target; property: "opacity"
                from: 1.0; to: 0.0
                duration: Kirigami.Units.shortDuration * 1.5
                easing.type: Easing.InQuad
            }
        }
        onFinished: root.closeFinished()
    }
}
