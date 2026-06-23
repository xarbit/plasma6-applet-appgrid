/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Entry point for the standalone `appgrid` executable, built the way KRunner
    builds its window: a PlasmaQuick PlasmaWindow (exposed to QML as
    PlasmaCore.Window) that hosts GridPanel as its mainItem. PlasmaWindow IS the
    Plasma dialog — it draws the translucent theme background, the blur and
    background-contrast, and the server-side theme shadow itself, so GridPanel
    runs in `nativePopup` mode (no background of its own) exactly like the panel
    plasmoid variant. Running in its own `appgrid` process, KWin derives the
    window class from the executable (not plasmashell), so every window
    open/close effect (Glide/Scale/Fade) animates it, like KRunner.

    Models, the bridge (the controller doubles as PlasmoidBridge) and the config
    object are injected from C++ as context properties (see src/standalone).
*/

import QtQuick

import org.kde.plasma.core as PlasmaCore

import "controllers"
import "views" as Views
import "js/constants.js" as Const

PlasmaCore.Window {
    id: win

    // Injected from C++ as this root's initial properties (main.cpp,
    // completeInitialization). Declared `required` so a missing or renamed
    // injection fails loudly at QML load rather than silently resolving to
    // undefined (#6). Typed `var` because the C++ classes aren't registered as
    // QML types — the daemon QML is a plain resource bundle, not a QML module.
    //   appGridController     — AppGridController (models + window glue + the same
    //                           method surface PlasmoidBridge forwards)
    //   appGridConfig         — the KConfigXT-generated AppGridConfig
    //   appGridStandalone     — single-instance bridge with show/hide/toggle signals
    //   appGridAutoShow       — open the launcher on startup (vs. wait for a toggle)
    //   appGridStartCompact   — open collapsed to the search bar
    required property var appGridController
    required property var appGridConfig
    required property var appGridStandalone
    required property bool appGridAutoShow
    required property bool appGridStartCompact

    visible: false
    color: "transparent"

    // PlasmaWindow positions mainItem inside its theme-frame padding but does not
    // size the window itself from QML (KRunner does that in C++); size it to the
    // panel's implicit size plus the padding so the layer surface has a real
    // width/height when it commits.
    width: panel.implicitWidth + leftPadding + rightPadding
    height: panel.implicitHeight + topPadding + bottomPadding

    ConfigCache { id: cfg; source: appGridConfig }

    // The structural appletInterface GridPanel expects.
    readonly property QtObject appletInterface: QtObject {
        property var dragSource: null
        readonly property bool isDragInFlight: dragSource ? dragSource.isDragInFlight : false
        function closeWindow() { win.closeWindow() }
    }

    // -- Content: GridPanel as the Plasma dialog's mainItem ----------------

    mainItem: Views.GridPanel {
        id: panel
        sizeToContent: true             // window is sized from implicitHeight; track compact
        // The "settings" header action routes here. openSettings() (not Configure)
        // keeps the owner plasmoid set when this launcher session was opened, so
        // its panel-button rows show. Goes through C++ so the settings window
        // loads in its own desktop-themed engine, not this Plasma-themed one.
        onConfigureRequested: appGridStandalone.openSettings()
        appletInterface: win.appletInterface
        appsModel: appGridController.appsModel
        searchModel: appGridController.searchModel
        runnerSourceModel: appGridController.runnerSourceModel
        configuration: appGridConfig
        plasmoidBridge: appGridController
        updateChecker: appGridController.isUniversalBuild ? appGridController.updateChecker : null
        favoritesClientInstance: Const.FAVORITES_CLIENT_ID
        sysInfoProvider: () => appGridController.systemInfo("Standalone")
        onCloseRequested: win.closeWindow()

        Component.onCompleted: {
            const ds = dragSourceComponent.createObject(panel)
            win.appletInterface.dragSource = ds
        }
    }

    property Component _dragSourceComponent: Component {
        id: dragSourceComponent
        DragSource {}
    }

    // Push the config-driven C++ toggles (search frecency/hidden, update check)
    // on init and on change — the same controller the plasmoid variants use.
    PlasmoidConfigSync {
        configuration: appGridConfig
        updateChecker: appGridController.isUniversalBuild ? appGridController.updateChecker : null
        bridge: appGridController
    }

    // -- Lifecycle ---------------------------------------------------------

    // compact=true opens collapsed to the search bar (the "Open in Compact Mode"
    // secondary shortcut); set before resetState / the margin calc so the panel
    // reports its compact height from frame one. Cleared on a normal open.
    function showWindow(compact) {
        panel.forceCompact = (compact === true)
        appGridController.configurePanelWindow(win)
        panel.resetState()
        updatePosition()
        closeOnDeactivate = false
        deactivateGuard.start()
        win.visible = true
        win.requestActivate()
        if (cfg.shakeOnOpen)
            panel.shakeAllIcons()
    }

    function closeWindow() {
        closeOnDeactivate = false
        deactivateGuard.stop()
        panel.resetOnClose()
        win.visible = false
    }

    // Place on the right screen + center vertically, atomically in C++ (KRunner's
    // model — see AppGridController::positionPanelWindow). The controller picks
    // the active output from KWin, sets the layer surface to it explicitly, and
    // sets the top margin from THAT screen's height — so screen and margin agree
    // and the panel never jumps across monitors. The FULL panelHeight is passed
    // (not the live/compact height): a compact panel hangs from the full panel's
    // top, and revealing the grid grows downward without drifting.
    function updatePosition() {
        const fullHeight = panel.panelHeight + win.topPadding + win.bottomPadding
        appGridController.positionPanelWindow(win, fullHeight, cfg.verticalOffset, cfg.openOnActiveScreen)
    }

    // Close on focus loss (debounced; ignores transient drops e.g. a virtual-
    // desktop switch), skipped briefly after open and during a drag-out.
    property bool closeOnDeactivate: false
    readonly property bool _dragInFlight: appletInterface.isDragInFlight
    Timer {
        id: deactivateGuard
        interval: 100
        onTriggered: win.closeOnDeactivate = true
    }
    Timer {
        id: closeDelay
        interval: 150
        onTriggered: if (win.visible && win.closeOnDeactivate && !win._dragInFlight && !win.active) win.closeWindow()
    }
    onActiveChanged: {
        if (win.active)
            closeDelay.stop()
        else if (win.closeOnDeactivate && !win._dragInFlight)
            closeDelay.restart()
    }

    Shortcut {
        sequence: "Escape"
        // Yield to an open folder: a window-level Shortcut outranks the folder
        // grid's Keys handler, so disable it while a folder is open. Esc then
        // closes just the folder; the window closes on the next Esc.
        enabled: win.visible && panel.openFolderId.length === 0
        onActivated: win.closeWindow()
    }

    // -- Single-instance D-Bus bridge -------------------------------------

    property Connections _instanceConn: Connections {
        target: appGridStandalone
        function onShowRequested() { win.showWindow() }
        function onHideRequested() { win.closeWindow() }
        function onToggleRequested() {
            if (win.visible)
                win.closeWindow()
            else
                win.showWindow()
        }
        // Secondary "Open in Compact Mode" shortcut: toggle, opening compact.
        function onToggleCompactRequested() {
            if (win.visible)
                win.closeWindow()
            else
                win.showWindow(true)
        }
        // configureRequested is handled in C++ (separate desktop-themed engine).
    }

    // The settings window edits the shared appGridConfig from its own process-
    // local engine; re-push the model-driven settings (hidden filter, sort,
    // categories) when they change. Reactive bindings (blur, grid) self-update.
    property Connections _settingsConn: Connections {
        target: appGridConfig
        // Hidden-apps changes flow straight into the model via the shared
        // LaunchStateStore (AppGridController), so they are not re-synced here.
        function onSortModeChanged() { panel.syncModelFromConfig() }
        function onUseSystemCategoriesChanged() { panel.syncModelFromConfig() }
        function onSortFavoritesAlphabeticallyChanged() { panel.syncModelFromConfig() }
        function onSearchShowsHiddenChanged() { panel.syncModelFromConfig() }
        function onShowRecentAppsChanged() { panel.syncModelFromConfig() }
    }

    // Skipped when launched with --configure (appGridAutoShow=false): the daemon
    // opens straight into its settings window, the launcher waits for a toggle.
    // --compact (appGridStartCompact) opens collapsed: the compact-mode shortcut
    // fired while the daemon was not yet running.
    Component.onCompleted: if (appGridAutoShow) showWindow(appGridStartCompact)
}
