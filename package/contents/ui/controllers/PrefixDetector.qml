/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure-logic component that classifies the search bar input into a
    prefix mode (terminal/command/files/info/hidden/help) and extracts
    the trimmed argument. Used by GridPanel; covered by tst_PrefixDetector.qml.
*/

import QtQuick

QtObject {
    id: detector

    property string input: ""

    readonly property string mode: {
        var t = input
        if (t.startsWith("t:")) return "terminal"
        if (t.startsWith("i:")) return "info"
        if (t.startsWith("h:")) return "hidden"
        if (t.startsWith("?")) return "help"
        if (t.startsWith("/") || t.startsWith("~/")) return "files"
        if (t.startsWith(":")) return "command"
        return ""
    }

    readonly property bool isPrefixMode: mode !== ""

    readonly property string argument: {
        var t = input
        if (mode === "terminal") return t.substring(2).trim()
        if (mode === "command") return t.substring(1).trim()
        if (mode === "files") return t.trim()
        return ""
    }
}
