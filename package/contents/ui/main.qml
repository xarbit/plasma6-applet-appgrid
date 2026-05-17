/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Root plasmoid item: panel icon + custom Window lifecycle.
    The window opens as a centered popup over a dim overlay; see GridWindow.qml.
*/

import QtQuick
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: kicker

    compactRepresentation: compactRepresentationComponent
    fullRepresentation: Item {}
    preferredRepresentation: compactRepresentation

    activationTogglesExpanded: false

    Plasmoid.icon: Plasmoid.configuration.useCustomButtonImage
        ? Plasmoid.configuration.customButtonImage
        : Plasmoid.configuration.icon

    property GridWindow gridWindow: null
    property bool gridOpen: false

    // Shared drag source for all app drags — see DragSource.qml.
    readonly property alias dragSource: dragSourceImpl
    readonly property alias isDragInFlight: dragSourceImpl.isDragInFlight
    DragSource { id: dragSourceImpl }

    // Update checker (universal builds only — Plasmoid.updateChecker is
    // nullptr on distro packages where the package manager handles updates).
    // We push the config's opt-in state into the checker on startup + on
    // changes; the C++ side throttles + defers the first network request.
    Component.onCompleted: _syncUpdateChecker()
    Connections {
        target: Plasmoid.configuration
        function onCheckForUpdatesChanged() { kicker._syncUpdateChecker() }
    }
    function _syncUpdateChecker() {
        if (Plasmoid.updateChecker)
            Plasmoid.updateChecker.enabled = Plasmoid.configuration.checkForUpdates === true
    }

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {}
    }

    Connections {
        target: Plasmoid
        function onActivated() { kicker.toggleWindow() }
    }


    function destroyGridWindow() {
        if (gridWindow) {
            gridWindow.visible = false
            gridWindow.destroy()
            gridWindow = null
        }
        gridOpen = false
    }

    function toggleWindow() {
        if (gridOpen) {
            closeWindow()
        } else {
            openWindow()
        }
    }

    function openWindow() {
        gridOpen = true
        if (!gridWindow)
            gridWindow = gridWindowComponent.createObject(kicker, { appletInterface: kicker })
        gridWindow.showGrid()
    }

    function closeWindow() {
        gridOpen = false
        if (gridWindow)
            gridWindow.closeGrid()
    }

    Component {
        id: gridWindowComponent
        GridWindow {}
    }
}
