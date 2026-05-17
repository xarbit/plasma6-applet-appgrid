/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Overlay window for fullscreen and centered popup display modes.
    Wayland: LayerShellQt (via C++ configureWindow/updateWindowScreen) handles
             overlay layer, screen selection, and window sizing.
    X11:     configureWindow sets frameless/stay-on-top/skip-taskbar flags;
             showGrid() positions the window using targetScreenGeometry().
*/

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Window {
    id: root

    property var appletInterface: null

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
    readonly property real estCellHeight: gridIconSize + Kirigami.Units.gridUnit * 3 + Kirigami.Units.smallSpacing * 2
    readonly property real estPanelWidth: estCellWidth * columns + Kirigami.Units.largeSpacing * 4
    readonly property real estPanelHeight: estCellHeight * rows + Kirigami.Units.largeSpacing * 4 + Kirigami.Units.gridUnit * 5

    // Wayland: LayerShell overrides these. X11: showGrid() overrides via targetScreenGeometry().
    width: Screen.width
    height: Screen.height
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

    onWidthChanged: if (visible && (!animLoader.item || animLoader.item.blurBeforeAnimation)) applyBlur()
    onHeightChanged: if (visible && (!animLoader.item || animLoader.item.blurBeforeAnimation)) applyBlur()

    // -----------------------------------------------------------------------
    // Grid lifecycle
    // -----------------------------------------------------------------------

    readonly property bool animationsEnabled: Kirigami.Units.longDuration > 0

    // Animation styles
    readonly property var animationFiles: [
        "animations/NoneAnimation.qml",      // 0
        "animations/FadeAnimation.qml",       // 1
        "animations/ScaleAnimation.qml",      // 2 (default)
        "animations/PopAnimation.qml",        // 3
        "animations/SlideUpAnimation.qml",    // 4
        "animations/SlideDownAnimation.qml",  // 5
        "animations/GlideAnimation.qml",      // 6
        "animations/BuzzAnimation.qml",       // 7
        "animations/TwistAnimation.qml",      // 8
        "animations/SlamAnimation.qml",       // 9
        "animations/GrowUpAnimation.qml"      // 10
    ]
    readonly property int animStyle: {
        var idx = Plasmoid.configuration.openAnimation
        if (idx === undefined || idx === null) idx = 2
        return Math.max(0, Math.min(idx, animationFiles.length - 1))
    }

    Loader {
        id: animLoader
        source: animationFiles[animStyle]
        onLoaded: {
            item.target = panel
            item.openFinished.connect(function() {
                if (!item.blurBeforeAnimation)
                    applyBlur()
                if (Plasmoid.configuration.shakeOnOpen)
                    panel.shakeAllIcons()
            })
            item.closeFinished.connect(function() {
                root.visible = false
                panel.opacity = 0.0
                dimOverlay.opacity = 0.0
                panel.scale = 1.0
                panel.rotation = 0
                panel.anchors.verticalCenterOffset = 0
                panel.transformOrigin = Item.Center
            })
        }
    }

    // Dim overlay fade animations
    NumberAnimation {
        id: dimFadeIn
        target: dimOverlay
        property: "opacity"
        from: 0; to: 1
        duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: dimFadeOut
        target: dimOverlay
        property: "opacity"
        from: 1; to: 0
        duration: Kirigami.Units.longDuration
        easing.type: Easing.InCubic
    }

    Timer {
        id: deactivateGuard
        interval: 100
        onTriggered: closeOnDeactivate = true
    }

    function showGrid() {
        if (!windowConfigured) {
            Plasmoid.configureWindow(root)
            windowConfigured = true
        }

        var useActive = Plasmoid.configuration.openOnActiveScreen !== false

        if (Plasmoid.isWayland) {
            Plasmoid.updateWindowScreen(root, useActive)
        } else {
            // X11: position window on the target screen manually
            var geo = Plasmoid.targetScreenGeometry(useActive)
            root.x = geo.x
            root.y = geo.y
            root.width = geo.width
            root.height = geo.height
        }

        // Delay close-on-deactivate to avoid reconfig race
        closeOnDeactivate = false
        deactivateGuard.start()

        // Reset all animatable properties to clean state
        panel.scale = 1.0
        panel.rotation = 0
        panel.anchors.verticalCenterOffset = 0

        panel.resetState()

        if (!animationsEnabled || animStyle === 0) {
            // No animation — show instantly
            panel.opacity = 1.0
            dimOverlay.opacity = 1.0
            visible = true
            requestActivate()
            applyBlur()
            if (Plasmoid.configuration.shakeOnOpen)
                panel.shakeAllIcons()
        } else {
            panel.opacity = 0.0
            dimOverlay.opacity = 0.0
            visible = true
            dimFadeIn.start()
            if (animLoader.item.blurBeforeAnimation)
                applyBlur()
            requestActivate()
            animLoader.item.open()
        }
    }

    function closeGrid() {
        closeOnDeactivate = false
        deactivateGuard.stop()
        Plasmoid.setBlurBehind(root, false, 0, 0, 0, 0, 0)
        if (animationsEnabled && animStyle !== 0 && animLoader.item) {
            dimFadeOut.start()
            animLoader.item.close()
        } else {
            root.visible = false
            panel.opacity = 0.0
            dimOverlay.opacity = 0.0
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // Close when window loses focus (skip briefly after open to avoid LayerShell
    // reconfig race; also skip while a drag-out is in flight so the platform DnD
    // isn't cancelled by the source window disappearing mid-drag).
    property bool closeOnDeactivate: false
    readonly property bool _dragInFlight: appletInterface
        && appletInterface.favoritesDragProxy
        && appletInterface.favoritesDragProxy.Drag.active
    onActiveChanged: {
        if (!active && visible && closeOnDeactivate && !_dragInFlight) {
            if (appletInterface)
                appletInterface.closeWindow()
        }
    }
    // When a drag-out finishes, close the window if it had lost focus during
    // the drag. Without this, the window would linger after the user drops on
    // an external target.
    //
    // Also flip the window into pointer pass-through mode for the lifetime of
    // the drag: AppGrid's layer-shell surface covers the full screen, so the
    // taskbar/panel/desktop are *underneath* us. Without pass-through the
    // user cannot reach those drop targets — the drag advertises mime fine
    // but the only surface receiving pointer events is AppGrid itself, so
    // the cursor never lands on an acceptor (verified via WAYLAND_DEBUG).
    on_DragInFlightChanged: {
        if (_dragInFlight) {
            // Shrink input region to the visible grid panel so the dim area
            // around it becomes pass-through. The user can drop on the
            // taskbar/panel/desktop underneath while internal favorites
            // reorder still receives drag events inside the panel rect.
            const pw = Math.round(panel.width)
            const ph = Math.round(panel.height)
            const px = Math.round((root.width - pw) / 2)
            const py = Math.round((root.height - ph) / 2)
            Plasmoid.setInputRect(root, px, py, pw, ph)
        } else {
            // Drag ended — restore full-window input.
            Plasmoid.setInputRect(root, 0, 0, 0, 0)
        }
        if (!_dragInFlight && !active && visible && closeOnDeactivate
                && appletInterface) {
            appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Background (dim overlay + click to close)
    // -----------------------------------------------------------------------

    Rectangle {
        id: dimOverlay
        anchors.fill: parent
        color: Plasmoid.configuration.dimBackground !== false
               ? Qt.rgba(0, 0, 0, 0.35)
               : "transparent"
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.appletInterface)
                    root.appletInterface.closeWindow()
            }
        }
    }

    // -----------------------------------------------------------------------
    // Main panel
    // -----------------------------------------------------------------------

    GridPanel {
        id: panel
        anchors.centerIn: parent
        opacity: 0.0
        transformOrigin: Item.Center
        appletInterface: root.appletInterface
        onCloseRequested: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Animations
    // -----------------------------------------------------------------------

}
