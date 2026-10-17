/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Takes the search field's text to the two searches behind it, without
    ever blocking the field:

    - the app grid filter and ranking (the view state's search text) runs
      once per event-loop turn, so a burst of keystrokes filters once;
    - KRunner (which runs every enabled runner in-process) gets the first
      character of a fresh query at once, so results start landing, and
      further keystrokes after a short trailing debounce. It only runs with
      the extra runners on and outside prefix modes.
*/

import QtQuick

QtObject {
    id: pipeline

    // --- Inputs ---

    property var viewState: null
    // The KRunner results model (its queryString drives the runners).
    property var runnerSourceModel: null
    // "Use extra runners" (cfg.useExtraRunners).
    property bool useExtraRunners: false
    property bool isPrefixMode: false

    // Short enough to feel live, long enough to collapse a fast-typed query
    // into a single runner query.
    property int runnerDebounceMs: 50

    // The latest field text.
    property string text: ""

    function setText(newText) {
        text = newText
        Qt.callLater(_applyToGrid)

        if (_runnerSearching()) {
            // Leading edge: KRunner still idle → fire now; later keystrokes
            // ride the trailing debounce.
            if (runnerSourceModel && runnerSourceModel.queryString.length === 0) {
                _runnerDebounce.stop()
                _applyToRunner()
            } else {
                _runnerDebounce.restart()
            }
        } else if (runnerSourceModel) {
            _runnerDebounce.stop()
            runnerSourceModel.queryString = ""
        }
    }

    // Filter the grid with the latest text now, if that is still pending. A
    // key that acts on the results (Enter, Down, …) can arrive in the same
    // batch of input events as the last keystroke, before the deferred pass;
    // it calls this first so it acts on the results of what was typed.
    function flush() {
        if (viewState && viewState.searchText !== text)
            _applyToGrid()
    }

    function _runnerSearching() {
        return text.length > 0 && !isPrefixMode && useExtraRunners
    }

    function _applyToGrid() {
        if (viewState)
            viewState.setSearchText(text)
    }

    function _applyToRunner() {
        if (runnerSourceModel)
            runnerSourceModel.queryString = _runnerSearching() ? text : ""
    }

    property Timer _runnerDebounce: Timer {
        interval: pipeline.runnerDebounceMs
        onTriggered: pipeline._applyToRunner()
    }
}
