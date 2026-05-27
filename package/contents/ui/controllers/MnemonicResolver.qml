/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure-logic component that assigns Alt+letter mnemonics to a list of
    labels (first unused uppercase letter wins). Used by CategoryBar;
    covered by tst_MnemonicResolver.qml.
*/

import QtQuick

QtObject {
    id: resolver

    // Ordered list of labels. Index in map indicates assignment.
    property var names: []

    readonly property var map: {
        var used = {}
        var m = {}
        for (var i = 0; i < names.length; i++) {
            var name = names[i]
            for (var j = 0; j < name.length; j++) {
                var ch = name.charAt(j).toUpperCase()
                if (ch >= 'A' && ch <= 'Z' && !used[ch]) {
                    used[ch] = true
                    m[ch] = name
                    break
                }
            }
        }
        return m
    }

    // Returns the index of the assigned mnemonic letter in `name`, or -1.
    function indexFor(name) {
        for (var letter in map) {
            if (map[letter] === name)
                return name.toUpperCase().indexOf(letter)
        }
        return -1
    }

    // Returns the name with the mnemonic letter wrapped in <u>...</u>,
    // or the plain name when no mnemonic was assigned.
    function richTextFor(name) {
        var idx = indexFor(name)
        if (idx < 0) return name
        return name.substring(0, idx)
            + "<u>" + name.charAt(idx) + "</u>"
            + name.substring(idx + 1)
    }

    // Resolves a key code (Qt.Key_A..Qt.Key_Z) to the assigned name, or "".
    function nameForKey(key) {
        var letter = String.fromCharCode(key).toUpperCase()
        return map[letter] || ""
    }
}
