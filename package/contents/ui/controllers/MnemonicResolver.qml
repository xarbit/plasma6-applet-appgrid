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

    // Ordered list of names. Index in map indicates assignment.
    property var names: []
    // (name) -> the label its letter is picked from; null: the name itself.
    property var labelOf: null

    function _label(name) {
        return labelOf ? labelOf(name) : name
    }

    readonly property var map: {
        var used = {}
        var m = {}
        for (var i = 0; i < names.length; i++) {
            var name = names[i]
            var label = _label(name)
            for (var j = 0; j < label.length; j++) {
                var ch = label.charAt(j).toUpperCase()
                if (ch >= 'A' && ch <= 'Z' && !used[ch]) {
                    used[ch] = true
                    m[ch] = name
                    break
                }
            }
        }
        return m
    }

    // Returns the index of the assigned mnemonic letter in the label of
    // `name`, or -1.
    function indexFor(name) {
        for (var letter in map) {
            if (map[letter] === name)
                return _label(name).toUpperCase().indexOf(letter)
        }
        return -1
    }

    // Returns the label of `name` with the mnemonic letter wrapped in
    // <u>...</u>, or the plain label when no mnemonic was assigned.
    function richTextFor(name) {
        var label = _label(name)
        var idx = indexFor(name)
        if (idx < 0) return label
        return label.substring(0, idx)
            + "<u>" + label.charAt(idx) + "</u>"
            + label.substring(idx + 1)
    }

    // Resolves a key code (Qt.Key_A..Qt.Key_Z) to the assigned name, or "".
    function nameForKey(key) {
        var letter = String.fromCharCode(key).toUpperCase()
        return map[letter] || ""
    }
}
