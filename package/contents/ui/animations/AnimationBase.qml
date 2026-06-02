/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared shell for the open/close animations GridWindow loads by name: the
    target handle, the effects-ordering flag, and the finished signals.
    Concrete animations derive from this and supply their own open()/close()
    (and reset() when they leave the target in a non-default state).
*/

import QtQuick

Item {
    id: root

    property Item target: null
    // True = GridWindow applies the blur/contrast background effects before
    // the open animation runs. Concrete animations override as needed.
    property bool effectsBeforeAnimation: false
    signal openFinished()
    signal closeFinished()

    function reset() {}
}
