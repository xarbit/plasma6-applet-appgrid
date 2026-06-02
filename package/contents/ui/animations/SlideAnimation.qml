/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Slides the target from off-screen to its centered position and back out
    on close. `direction` picks the side: +1 rises from below center, -1
    descends from above. SlideUpAnimation / SlideDownAnimation are thin
    wrappers that only set this.
*/

import QtQuick
import org.kde.kirigami as Kirigami

AnimationBase {
    id: root

    // +1 = slide up from below center, -1 = slide down from above.
    property int direction: 1

    // Signed off-screen travel distance; falls back to a screen-height
    // estimate when the target isn't parented yet.
    readonly property real slideDistance: (target && target.parent
        ? target.parent.height : 800) * direction

    function open() {
        target.opacity = 1.0
        openAnim.start()
    }
    function close() { closeAnim.start() }

    NumberAnimation {
        id: openAnim
        target: root.target; property: "anchors.verticalCenterOffset"
        from: root.slideDistance; to: 0; duration: Kirigami.Units.longDuration * 1.5
        easing.type: Easing.OutCubic
        onFinished: root.openFinished()
    }

    NumberAnimation {
        id: closeAnim
        target: root.target; property: "anchors.verticalCenterOffset"
        from: 0; to: root.slideDistance; duration: Kirigami.Units.shortDuration * 1.5
        easing.type: Easing.InCubic
        onFinished: root.closeFinished()
    }
}
