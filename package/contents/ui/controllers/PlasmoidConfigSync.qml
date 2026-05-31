/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pushes a handful of Plasmoid config knobs back into the C++ plasmoid
    (UpdateChecker enable, search frecency opt-in) on init and on every
    relevant configuration change. Lives here so both variant main.qml
    files stop duplicating the same sync wiring.
*/

import QtQuick
import org.kde.plasma.plasmoid

QtObject {
    function _sync() {
        if (Plasmoid.updateChecker)
            Plasmoid.updateChecker.enabled = Plasmoid.configuration.checkForUpdates === true
        Plasmoid.setSearchUsesFrecency(Plasmoid.configuration.searchUsesFrecency === true)
    }

    Component.onCompleted: _sync()

    property Connections _conn: Connections {
        target: Plasmoid.configuration
        function onCheckForUpdatesChanged() { _sync() }
        function onSearchUsesFrecencyChanged() { _sync() }
    }
}
