/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Overlay window for the centered popup display mode.
    Wayland: LayerShellQt (via C++ configureWindow/updateWindowScreen) handles
             overlay layer, screen selection, and window sizing.
    X11:     configureWindow sets frameless/stay-on-top/skip-taskbar flags;
             showGrid() positions the window using targetScreenGeometry().
*/

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

import "../controllers"

Window {
    id: root

    // Plasmoid root. Deliberately `var`, not typed as PlasmoidItem,
    // for two reasons: typing it would force every consumer to import
    // `org.kde.plasma.plasmoid`, and keeping the contract structural lets
    // tests pass plain QtObject mocks that expose the same properties
    // (dragSource, isDragInFlight, closeWindow(), …).
    property var appletInterface: null

    ConfigCache { id: cfg; source: root.configuration }

    // C++ models supplied by the owning plasmoid root; passed straight
    // through to GridPanel.
    required property var appsModel
    required property var searchModel
    required property var runnerSourceModel

    required property var configuration
    // Single Plasmoid-callback surface; see PlasmoidBridge.qml.
    required property var plasmoidBridge
    required property var updateChecker
    required property string favoritesClientInstance
    required property var sysInfo

    // Forwarded into GridPanel.forceCompact for the current session; the
    // owning plasmoid flips this before showGrid() when the secondary
    // shortcut fires, then resets it on close.
    property bool forceCompact: false

    readonly property real panelShadowMargin: Kirigami.Units.gridUnit * 2

    // User vertical nudge for the centered panel. The config value is a
    // percent (-100 = top, 0 = centered, +100 = bottom) of the free space
    // between the full panel and the screen edge, so it scales across
    // screen sizes and can never push the panel off-screen. Uses the full
    // panelHeight (not panel.height) so the compact-mode height animation
    // doesn't drag the panel up or down as it expands.
    readonly property real panelVerticalOffset: {
        var pct = cfg.verticalOffset
        var slack = Math.max(0, (root.height - panel.panelHeight) / 2)
        return Math.round(pct / 100 * slack)
    }

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

    // Geometry of the centered panel within the overlay window, including the
    // user vertical offset. Shared by the blur region and the drag input rect.
    function _panelRect() {
        const pw = Math.round(panel.width)
        const ph = Math.round(panel.height)
        return {
            x: Math.round((root.width - pw) / 2),
            y: Math.round((root.height - ph) / 2)
               + root.panelVerticalOffset
               + Math.round(panel.compactShift),
            w: pw,
            h: ph
        }
    }

    function applyBackgroundEffects() {
        if (cfg.effectiveEnableBlur && visible) {
            const r = _panelRect()
            root.plasmoidBridge.setBackgroundEffects(root, true, r.x, r.y, r.w, r.h, panel.radius)
        } else {
            root.plasmoidBridge.setBackgroundEffects(root, false, 0, 0, 0, 0, 0)
        }
    }

    onWidthChanged: if (visible && (!animLoader.item || animLoader.item.effectsBeforeAnimation)) applyBackgroundEffects()
    onHeightChanged: if (visible && (!animLoader.item || animLoader.item.effectsBeforeAnimation)) applyBackgroundEffects()

    // Compact-mode height animation changes panel.height while the overlay
    // window stays screen-sized; re-clip the blur region with it. No
    // open/close gate — the height animation runs after open finishes and
    // that gate would suppress the blur reapply mid-resize.
    Connections {
        target: panel
        function onHeightChanged() {
            if (root.visible)
                root.applyBackgroundEffects()
        }
    }

    // -----------------------------------------------------------------------
    // Grid lifecycle
    // -----------------------------------------------------------------------

    readonly property bool animationsEnabled: Kirigami.Units.longDuration > 0

    // Animation styles
    readonly property var animationFiles: [
        "../animations/NoneAnimation.qml",      // 0
        "../animations/FadeAnimation.qml",       // 1
        "../animations/ScaleAnimation.qml",      // 2 (default)
        "../animations/PopAnimation.qml",        // 3
        "../animations/SlideUpAnimation.qml",    // 4
        "../animations/SlideDownAnimation.qml",  // 5
        "../animations/GlideAnimation.qml",      // 6
        "../animations/BuzzAnimation.qml",       // 7
        "../animations/TwistAnimation.qml",      // 8
        "../animations/SlamAnimation.qml",       // 9
        "../animations/GrowUpAnimation.qml"      // 10
    ]
    readonly property int animStyle: Math.max(0, Math.min(cfg.openAnimation,
                                                          animationFiles.length - 1))

    Loader {
        id: animLoader
        source: animationFiles[animStyle]
        onLoaded: {
            item.target = panel
            item.openFinished.connect(function() {
                if (!item.effectsBeforeAnimation)
                    applyBackgroundEffects()
                if (cfg.shakeOnOpen)
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
            root.plasmoidBridge.configureWindow(root)
            windowConfigured = true
        }

        var useActive = cfg.openOnActiveScreen

        if (root.plasmoidBridge.isWayland) {
            root.plasmoidBridge.updateWindowScreen(root, useActive)
        } else {
            // X11: position window on the target screen manually
            var geo = root.plasmoidBridge.targetScreenGeometry(useActive)
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
            applyBackgroundEffects()
            if (cfg.shakeOnOpen)
                panel.shakeAllIcons()
        } else {
            panel.opacity = 0.0
            dimOverlay.opacity = 0.0
            visible = true
            dimFadeIn.start()
            if (animLoader.item.effectsBeforeAnimation)
                applyBackgroundEffects()
            requestActivate()
            animLoader.item.open()
        }
    }

    function closeGrid() {
        closeOnDeactivate = false
        deactivateGuard.stop()
        panel.resetOnClose()
        root.plasmoidBridge.setBackgroundEffects(root, false, 0, 0, 0, 0, 0)
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
        ? appletInterface.isDragInFlight : false
    onActiveChanged: {
        if (!active && visible && closeOnDeactivate && !_dragInFlight) {
            if (appletInterface)
                appletInterface.closeWindow()
        }
    }
    // While a drag-out is in flight, shrink the window's input region to the
    // visible grid panel so the dim area around it becomes pointer-pass-through.
    // AppGrid's layer-shell surface covers the full screen, so the taskbar/
    // panel/desktop are *underneath* us — without pass-through the cursor
    // never lands on an external drop target (verified via WAYLAND_DEBUG).
    // Reorder inside the panel rect still works because that area keeps input.
    //
    // The binding tracks panel geometry too, so if the panel resizes mid-drag
    // (orientation change, dynamic content) the input rect follows.
    function _applyDragInputRect() {
        if (_dragInFlight) {
            const r = _panelRect()
            root.plasmoidBridge.setInputRect(root, r.x, r.y, r.w, r.h)
        } else {
            root.plasmoidBridge.setInputRect(root, 0, 0, 0, 0)
        }
    }
    on_DragInFlightChanged: {
        _applyDragInputRect()
        // When a drag-out finishes, close the window if it had lost focus
        // during the drag. Otherwise the window would linger after the drop.
        if (!_dragInFlight && !active && visible && closeOnDeactivate
                && appletInterface) {
            appletInterface.closeWindow()
        }
    }
    Connections {
        target: panel
        enabled: root._dragInFlight
        function onWidthChanged()  { root._applyDragInputRect() }
        function onHeightChanged() { root._applyDragInputRect() }
    }
    Connections {
        target: root
        enabled: root._dragInFlight
        function onWidthChanged()  { root._applyDragInputRect() }
        function onHeightChanged() { root._applyDragInputRect() }
    }

    // -----------------------------------------------------------------------
    // Background (dim overlay + click to close)
    // -----------------------------------------------------------------------

    Rectangle {
        id: dimOverlay
        anchors.fill: parent
        color: cfg.effectiveDimBackground ? Qt.rgba(0, 0, 0, 0.35) : "transparent"
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
        appsModel: root.appsModel
        searchModel: root.searchModel
        runnerSourceModel: root.runnerSourceModel
        configuration: root.configuration
        plasmoidBridge: root.plasmoidBridge
        updateChecker: root.updateChecker
        favoritesClientInstance: root.favoritesClientInstance
        sysInfo: root.sysInfo
        forceCompact: root.forceCompact
        // Static user offset + compact-mode downward shift, kept out of
        // the anchor system so the open/close animations (which drive
        // anchors.verticalCenterOffset) are unaffected.
        transform: Translate {
            y: root.panelVerticalOffset + panel.compactShift
        }
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
