/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure-logic component that classifies the search bar input into a
    prefix mode (terminal/command/files/info/hidden/help) and extracts
    the trimmed argument. Used by GridPanel; covered by tst_PrefixDetector.qml.
*/

import QtQuick

import "../js/prefixmodes.js" as PrefixModes

QtObject {
    id: detector

    property string input: ""

    readonly property string mode: PrefixModes.modeFor(input)
    readonly property bool isPrefixMode: mode !== PrefixModes.NONE
    readonly property string argument: PrefixModes.argumentFor(input, mode)
}
