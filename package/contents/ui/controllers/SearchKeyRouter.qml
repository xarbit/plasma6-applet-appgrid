/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Where the keys pressed in the search field go. The field keeps focus while
    the user types, so Enter, the arrows, Tab and the paging keys act on what
    is shown below it: the search results, the shown grid, or a prefix mode's
    view. Pure routing — what it cannot do itself (launch a result, run a
    command, collapse the compact grid) it asks for with a signal.
*/

import QtQuick

import "../js/prefixmodes.js" as PrefixModes
import "../js/searchresultnav.js" as SearchResultNav

QtObject {
    id: router

    // The search results (SearchResultsList): currentIndex, count and its
    // paging functions.
    property var results: null
    // The shown grid, with enterFromSearch() / activateCurrent(), or null.
    property var keyView: null
    // The prefix mode's view, when one is built.
    property var prefixView: null
    property string prefixMode: PrefixModes.NONE
    readonly property bool _inPrefixMode: prefixMode !== PrefixModes.NONE
    // The results list is shown (searching, outside a prefix mode).
    property bool resultsShown: false
    property bool searching: false
    // Compact mode: whether the grid may collapse under the field, whether it
    // is collapsed now, and whether the user revealed it.
    property bool collapsible: false
    property bool collapsed: false
    property bool revealed: false

    // The SearchPipeline: each key first flushes the search still pending, so
    // it acts on the results of what was typed.
    property var pipeline: null

    signal launchResultRequested(int index)
    // A t: (inTerminal) or : command to run.
    signal runRequested(bool inTerminal)
    signal revealRequested(bool revealed)

    function _flush() {
        if (pipeline)
            pipeline.flush()
    }

    function accept() {
        _flush()
        if (prefixMode === PrefixModes.TERMINAL || prefixMode === PrefixModes.COMMAND) {
            runRequested(prefixMode === PrefixModes.TERMINAL)
        } else if (prefixMode === PrefixModes.FILES) {
            if (prefixView)
                prefixView.activateFileCurrent()
        } else if (_inPrefixMode) {
            return
        } else if (resultsShown) {
            if (results && results.count > 0)
                launchResultRequested(Math.max(0, results.currentIndex))
        } else if (keyView) {
            keyView.activateCurrent()
        }
    }

    function moveDown() {
        _flush()
        if (prefixMode === PrefixModes.FILES) {
            if (prefixView)
                prefixView.focusFileList()
        } else if (collapsed) {
            // The first Down reveals the compact grid, keeping focus here; the
            // next one moves into it.
            revealRequested(true)
        } else {
            _step(1, false)
        }
    }

    function moveUp() {
        _flush()
        if (resultsShown)
            _step(-1, false)
        else if (collapsible && revealed && !searching)
            revealRequested(false)
    }

    function tab() { _flush(); _step(1, true) }

    function pageUp() { _flush(); if (resultsShown) results.pageUp() }
    function pageDown() { _flush(); if (resultsShown) results.pageDown() }
    function home() { _flush(); if (resultsShown) results.goHome() }
    function end() { _flush(); if (resultsShown) results.goEnd() }

    // Alt+1..9 launches that search result.
    function altNumber(number) {
        _flush()
        if (resultsShown && results && number >= 1 && number <= results.count)
            launchResultRequested(number - 1)
    }

    // A prefix mode's view keeps its own keys.
    function _step(step, wrap) {
        if (_inPrefixMode)
            return
        if (resultsShown) {
            if (!results)
                return
            const next = SearchResultNav.nextIndex(results.currentIndex, results.count, step, wrap)
            if (next !== results.currentIndex)
                results.currentIndex = next
        } else if (keyView) {
            keyView.enterFromSearch()
        }
    }
}
