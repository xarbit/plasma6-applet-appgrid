/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

AnimationBase {
    id: root
    property bool effectsBeforeAnimation: true

    function open() {
        target.opacity = 1.0
        openFinished()
    }
    function close() { closeFinished() }
}
