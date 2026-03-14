/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Root plasmoid item: panel icon + overlay window lifecycle.
*/

import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: kicker

    // Match Kicker's dashboard pattern: icon is fullRepresentation,
    // compactRepresentation is null, preferredRepresentation forces
    // the fullRepresentation to be shown directly in the panel.
    compactRepresentation: null
    fullRepresentation: compactRepresentationComponent
    preferredRepresentation: fullRepresentation

    expandedOnDragHover: false
    hideOnWindowDeactivate: true
    activationTogglesExpanded: false

    Plasmoid.icon: Plasmoid.configuration.useCustomButtonImage
        ? Plasmoid.configuration.customButtonImage
        : Plasmoid.configuration.icon

    property GridWindow gridWindow: null
    property bool gridOpen: false

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {}
    }

    // Super key / external activation
    Connections {
        target: Plasmoid
        function onActivated() {
            kicker.toggleWindow()
        }
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
