/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Overlay window for fullscreen and centered popup display modes.
    Uses LayerShellQt (via C++ configureWindow) for the fullscreen Wayland overlay.
*/

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Window {
    id: root

    property var appletInterface: null

    readonly property bool isPopupMode: true
    readonly property real panelShadowMargin: Kirigami.Units.gridUnit * 2

    // Compute window size independently from panel to avoid circular dependencies.
    // Uses the same icon-based cell estimates as GridPanel.
    readonly property int columns: Plasmoid.configuration.gridColumns || 7
    readonly property int rows: Plasmoid.configuration.gridRows || 4
    readonly property real gridIconSize: {
        var preset = Plasmoid.configuration.iconSize
        if (preset === 0) return Kirigami.Units.iconSizes.medium
        if (preset === 1) return Kirigami.Units.iconSizes.large
        return Kirigami.Units.iconSizes.huge
    }
    readonly property real estCellWidth: gridIconSize + Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing * 2
    readonly property real estCellHeight: gridIconSize + Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing * 2
    readonly property real estPanelWidth: estCellWidth * columns + Kirigami.Units.largeSpacing * 4
    readonly property real estPanelHeight: estCellHeight * rows + Kirigami.Units.largeSpacing * 4 + Kirigami.Units.gridUnit * 5

    width: isPopupMode ? Math.min(estPanelWidth, Screen.width * 0.9) + panelShadowMargin * 2 : Screen.width
    height: isPopupMode ? Math.min(estPanelHeight, Screen.height * 0.9) + panelShadowMargin * 2 : Screen.height
    x: isPopupMode ? Math.round((Screen.width - width) / 2) : 0
    y: isPopupMode ? Math.round((Screen.height - height) / 2) : 0
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint | Qt.Tool

    property bool windowConfigured: false

    // -----------------------------------------------------------------------
    // Blur management
    // -----------------------------------------------------------------------

    function applyBlur() {
        if (Plasmoid.configuration.enableBlur && visible) {
            var pw = Math.round(panel.width)
            var ph = Math.round(panel.height)
            var px = Math.round((root.width - pw) / 2)
            var py = Math.round((root.height - ph) / 2)
            Plasmoid.setBlurBehind(root, true, px, py, pw, ph, panel.radius)
        } else {
            Plasmoid.setBlurBehind(root, false, 0, 0, 0, 0, 0)
        }
    }

    onWidthChanged: if (visible) applyBlur()
    onHeightChanged: if (visible) applyBlur()

    // -----------------------------------------------------------------------
    // Grid lifecycle
    // -----------------------------------------------------------------------

    function showGrid() {
        if (!windowConfigured) {
            Plasmoid.configureWindow(root)
            windowConfigured = true
        }
        panel.resetState()
        visible = true
        applyBlur()
        requestActivate()
        openAnim.start()
    }

    function closeGrid() {
        closeAnim.start()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // In popup mode, close when window loses focus
    onActiveChanged: {
        if (isPopupMode && !active && visible) {
            if (appletInterface)
                appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Background (click to close in fullscreen mode)
    // -----------------------------------------------------------------------

    MouseArea {
        anchors.fill: parent
        visible: !root.isPopupMode
        onClicked: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Main panel
    // -----------------------------------------------------------------------

    GridPanel {
        id: panel
        anchors.centerIn: parent
        opacity: 0.0
        scale: 1.15
        transformOrigin: Item.Center
        onCloseRequested: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Animations
    // -----------------------------------------------------------------------

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: panel; property: "scale"
            from: 1.15; to: 1.0; duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: panel; property: "opacity"
            from: 0.0; to: 1.0; duration: 120
            easing.type: Easing.OutCubic
        }
        onFinished: {
            if (Plasmoid.configuration.shakeOnOpen)
                panel.shakeAllIcons()
        }
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: panel; property: "scale"
            from: 1.0; to: 1.12; duration: 120
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: panel; property: "opacity"
            from: 1.0; to: 0.0; duration: 120
            easing.type: Easing.InCubic
        }
        onFinished: {
            root.visible = false
            panel.scale = 1.15
            panel.opacity = 0.0
        }
    }
}
