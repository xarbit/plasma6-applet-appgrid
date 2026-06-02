/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

AnimationBase {
    id: root

    function open() { openAnim.start() }
    function close() { closeAnim.start() }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: root.target; property: "scale"
            from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration * 1.5
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root.target; property: "rotation"
            from: 180; to: 0; duration: Kirigami.Units.longDuration * 1.5
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root.target; property: "opacity"
            from: 0.0; to: 1.0; duration: Kirigami.Units.longDuration * 0.8
            easing.type: Easing.OutQuad
        }
        onFinished: root.openFinished()
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: root.target; property: "scale"
            from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration * 1.5
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root.target; property: "rotation"
            from: 0; to: -180; duration: Kirigami.Units.shortDuration * 1.5
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root.target; property: "opacity"
            from: 1.0; to: 0.0; duration: Kirigami.Units.shortDuration * 1.2
            easing.type: Easing.InQuad
        }
        onFinished: root.closeFinished()
    }
}
