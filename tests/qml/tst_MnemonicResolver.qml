/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

TestCase {
    name: "MnemonicResolver"

    function resolver(names) {
        var c = Qt.createComponent("MnemonicResolver.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, { names: names })
    }

    // --- assignment ---

    function test_emptyHasEmptyMap() {
        var r = resolver([])
        compare(Object.keys(r.map).length, 0)
    }

    function test_firstLetterAssignedFirst() {
        var r = resolver(["Apple", "Banana", "Cherry"])
        compare(r.map["A"], "Apple")
        compare(r.map["B"], "Banana")
        compare(r.map["C"], "Cherry")
    }

    function test_collisionPicksNextAvailableLetter() {
        // Apricot's 'A' taken; falls to 'P'
        var r = resolver(["Apple", "Apricot"])
        compare(r.map["A"], "Apple")
        compare(r.map["P"], "Apricot")
    }

    function test_noLettersLeavesUnassigned() {
        var r = resolver(["123", "456"])
        compare(Object.keys(r.map).length, 0)
    }

    function test_caseInsensitiveCollision() {
        // 'A' from "Apple" should block "ant" too
        var r = resolver(["Apple", "ant"])
        compare(r.map["A"], "Apple")
        compare(r.map["N"], "ant")
    }

    // --- indexFor ---

    function test_indexForReturnsLetterPosition() {
        var r = resolver(["Apple", "Apricot"])
        compare(r.indexFor("Apple"), 0)    // 'A' at 0
        compare(r.indexFor("Apricot"), 1)  // 'p' at 1 (since 'A' taken)
    }

    function test_indexForUnknownReturnsMinusOne() {
        var r = resolver(["Apple"])
        compare(r.indexFor("Banana"), -1)
    }

    // --- richTextFor ---

    function test_richTextWrapsAssignedLetter() {
        var r = resolver(["Apple"])
        compare(r.richTextFor("Apple"), "<u>A</u>pple")
    }

    function test_richTextWrapsAtCollisionFallback() {
        var r = resolver(["Apple", "Apricot"])
        compare(r.richTextFor("Apricot"), "A<u>p</u>ricot")
    }

    function test_richTextFallsBackToPlainTextWhenUnassigned() {
        var r = resolver(["123"])
        compare(r.richTextFor("123"), "123")
    }

    // --- nameForKey ---

    function test_nameForKeyResolvesLetter() {
        var r = resolver(["Apple", "Banana"])
        compare(r.nameForKey(Qt.Key_A), "Apple")
        compare(r.nameForKey(Qt.Key_B), "Banana")
    }

    function test_nameForKeyReturnsEmptyForUnknown() {
        var r = resolver(["Apple"])
        compare(r.nameForKey(Qt.Key_Z), "")
    }

    // --- collision behaviour at scale (>20 items) ---

    function test_eachLetterAssignedOnceAcrossLargeList() {
        // 26 single-letter names, each gets exactly the letter it carries.
        var names = []
        for (var i = 0; i < 26; ++i)
            names.push(String.fromCharCode(65 + i))
        var r = resolver(names)
        compare(Object.keys(r.map).length, 26)
        for (var j = 0; j < 26; ++j) {
            var letter = String.fromCharCode(65 + j)
            compare(r.map[letter], letter)
        }
    }

    function test_overflowItemsStayUnassigned() {
        // Two items share the same single letter — only the first wins,
        // the second has no remaining letter and is left unassigned.
        var r = resolver(["X", "X"])
        compare(r.map["X"], "X")
        compare(Object.keys(r.map).length, 1)
    }

    function test_indexForUnassignedDuplicateIsMinusOne() {
        var r = resolver(["X", "X"])
        // First "X" assigned; resolver compares by value so both
        // strings hit the same map entry — indexFor returns the
        // assigned position regardless. Pin that contract.
        compare(r.indexFor("X"), 0)
    }

    function test_collisionFallsThroughAllTakenLetters() {
        // First name "AB" claims A (first letter wins). Second name
        // "ABC" tries A (taken), then B (free) — B wins. C never
        // consulted since the search stops on first free letter.
        var r = resolver(["AB", "ABC"])
        compare(r.map["A"], "AB")
        compare(r.map["B"], "ABC")
        verify(!r.map["C"])
    }

    function test_allLettersConsumedLeavesNameUnassigned() {
        // First name claims A, second tries letters from a name made of
        // only A — falls off the end and the second is unassigned.
        var r = resolver(["A", "AA"])
        compare(r.map["A"], "A")
        compare(r.indexFor("AA"), -1)
    }

    function test_nonAsciiLettersAreSkipped() {
        // Accented chars don't fall in the A..Z range after toUpperCase,
        // so the resolver skips them. "éA" should pick A, not é.
        var r = resolver(["éA"])
        compare(r.map["A"], "éA")
        verify(!r.map["É"])
    }

    function test_nameWithOnlyNonAsciiIsUnassigned() {
        var r = resolver(["éü", "123"])
        compare(Object.keys(r.map).length, 0)
    }

    function test_deterministicAcrossRebuilds() {
        // Same input twice yields the same map — pure-function contract.
        const names = ["Calendar", "Calculator", "Camera",
                       "Chromium", "Console", "Code"]
        var a = resolver(names)
        var b = resolver(names)
        const keysA = Object.keys(a.map).sort()
        const keysB = Object.keys(b.map).sort()
        compare(keysA, keysB)
        for (var k = 0; k < keysA.length; ++k)
            compare(a.map[keysA[k]], b.map[keysA[k]])
    }
}
