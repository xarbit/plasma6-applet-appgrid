/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pushes a handful of config knobs back into the C++ plasmoid (UpdateChecker
    enable, search frecency opt-in, search-shows-hidden) on init and on every
    relevant configuration change. Lives here so both variant main.qml files
    stop duplicating the same sync wiring.

    Dependencies are injected (configuration handle, updateChecker, the
    PlasmoidBridge for the setters) rather than reached through Plasmoid.*, so
    this stays consistent with the other controllers and can be stubbed.
*/

import QtQuick

QtObject {
    id: sync

    required property var configuration
    required property var updateChecker
    required property var bridge

    function _sync() {
        if (updateChecker)
            updateChecker.enabled = configuration.checkForUpdates === true
        bridge.setSearchUsesFrecency(configuration.searchUsesFrecency === true)
        bridge.setSearchShowsHidden(configuration.searchShowsHidden === true)
        bridge.setActivityScopingEnabled(configuration.enableActivities === true)
    }

    Component.onCompleted: _sync()

    property Connections _conn: Connections {
        target: sync.configuration
        function onCheckForUpdatesChanged() { sync._sync() }
        function onSearchUsesFrecencyChanged() { sync._sync() }
        function onSearchShowsHiddenChanged() { sync._sync() }
        function onEnableActivitiesChanged() { sync._sync() }
    }
}
