/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

Item {
    id: root
    property Item target: null
    property bool effectsBeforeAnimation: true
    signal openFinished()
    signal closeFinished()

    function open() {
        target.opacity = 1.0
        openFinished()
    }
    function close() { closeFinished() }
    function reset() {}
}
