/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for categoryflatten.js — flattening grouped apps into the nav list
    plus the prefix-sum section starts, and the inverse flat-index -> section
    lookup. Locks the perf-sensitive algorithm (boundaries, empty sections).
*/

import QtQuick
import QtTest
import "categoryflatten.js" as CategoryFlatten

TestCase {
    name: "CategoryFlatten"

    // --- flatten ---

    function test_flattenConcatsAndPrefixSums() {
        const r = CategoryFlatten.flatten([
            { category: "A", apps: [1, 2] },
            { category: "B", apps: [3, 4, 5] },
        ])
        compare(r.flatApps.join(","), "1,2,3,4,5")
        compare(r.sectionStartIndices.join(","), "0,2")
    }

    function test_flattenSingleSection() {
        const r = CategoryFlatten.flatten([{ category: "A", apps: [1, 2, 3] }])
        compare(r.flatApps.length, 3)
        compare(r.sectionStartIndices.join(","), "0")
    }

    function test_flattenEmptyInput() {
        const r = CategoryFlatten.flatten([])
        compare(r.flatApps.length, 0)
        compare(r.sectionStartIndices.length, 0)
    }

    function test_flattenNullInput() {
        const r = CategoryFlatten.flatten(null)
        compare(r.flatApps.length, 0)
        compare(r.sectionStartIndices.length, 0)
    }

    function test_flattenTreatsAbsentAppsKeyAsEmpty() {
        // A group object with no `apps` key at all → treated as an empty
        // section (apps || []), not a crash.
        const r = CategoryFlatten.flatten([
            { category: "A", apps: [1] },
            { category: "B" },
            { category: "C", apps: [2] },
        ])
        compare(r.flatApps.join(","), "1,2")
        compare(r.sectionStartIndices.join(","), "0,1,1")
    }

    function test_flattenEmptySectionInMiddle() {
        // An empty middle section repeats the running offset as its start.
        const r = CategoryFlatten.flatten([
            { category: "A", apps: [1] },
            { category: "B", apps: [] },
            { category: "C", apps: [2, 3] },
        ])
        compare(r.flatApps.join(","), "1,2,3")
        compare(r.sectionStartIndices.join(","), "0,1,1")
    }

    // --- sectionForFlatIndex ---

    function test_sectionLookupAtBoundaries() {
        const starts = [0, 2, 5]
        compare(CategoryFlatten.sectionForFlatIndex(0, starts), 0)
        compare(CategoryFlatten.sectionForFlatIndex(1, starts), 0)
        compare(CategoryFlatten.sectionForFlatIndex(2, starts), 1)  // section boundary
        compare(CategoryFlatten.sectionForFlatIndex(4, starts), 1)
        compare(CategoryFlatten.sectionForFlatIndex(5, starts), 2)  // section boundary
        compare(CategoryFlatten.sectionForFlatIndex(9, starts), 2)
    }

    function test_sectionLookupSkipsEmptySection() {
        // starts [0,1,1]: section 1 is empty, so flat index 1 belongs to 2.
        const starts = [0, 1, 1]
        compare(CategoryFlatten.sectionForFlatIndex(0, starts), 0)
        compare(CategoryFlatten.sectionForFlatIndex(1, starts), 2)
    }

    function test_sectionLookupNegativeIsMinusOne() {
        compare(CategoryFlatten.sectionForFlatIndex(-1, [0, 2]), -1)
    }

    function test_sectionLookupEmptyStartsIsMinusOne() {
        compare(CategoryFlatten.sectionForFlatIndex(0, []), -1)
    }
}
