/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppGrid's own settings window (the daemon's, not the Plasma applet config).
    Loaded by main.cpp in its OWN QQmlApplicationEngine (without the launcher's
    "_kirigamiTheme=Plasma"), so it is themed like a normal KDE app / KRunner's
    config — the system colour scheme — not the Plasma desktop theme.

    It hosts the EXACT SAME page bodies as the Plasma applet's settings dialog:
    the shared, Plasmoid-free Config*Content components under contents/ui/config/.
    A vertical category sidebar (System Settings style) switches a StackLayout of
    those bodies; a footer button row (Defaults / Reset / Cancel / Apply / OK)
    buffers the edits against the shared AppGridConfig.

    Buffering — standard KCM behaviour: edits do NOT touch the launcher until the
    user hits Apply/OK, and Apply/Reset stay disabled until something changed.
    The pages edit a SEPARATE AppGridConfig instance (appGridConfigBuffer, from
    main.cpp); the launcher reads the live appGridConfig. So:
      * open / Reset  -> copy live -> buffer (_syncFromLive), the pages now mirror
        what is saved;
      * the user edits the buffer freely, nothing reaches the launcher;
      * Apply / OK     -> copy buffer -> live + live.save() (_apply); only now does
        the launcher re-sync (Connections in Main.qml) and the file persist;
      * Defaults       -> write each buffer property from its defaultXValue (a
        generated CONSTANT Q_PROPERTY) — staged in the buffer, not applied;
      * Cancel         -> just close; the next open re-syncs from live, discarding
        the staged edits.
    `dirty` compares buffer vs live per key (JSON.stringify handles the list keys
    hiddenApps/headerActions); the binding reads both sides so it re-evaluates on
    any change. After a bulk copy we bump `revision`; the Content bindings read
    through it so combo/spin internal state stays honest after a multi-key change.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Window

import org.kde.kirigami as Kirigami

import "config"
import "js/configbuffer.js" as ConfigBuffer

Kirigami.ApplicationWindow {
    id: win

    // Injected from C++ as this root's initial properties (main.cpp,
    // setInitialProperties). Declared `required` so a missing or renamed
    // injection fails loudly at QML load rather than silently resolving to
    // undefined (#6).
    //   appGridConfig       — the live AppGridConfig (read on open, written on Apply)
    //   appGridConfigBuffer — the staging AppGridConfig the pages edit
    //   appGridController   — exposes availableShells() / isUniversalBuild / appsModel
    required property var appGridConfig
    required property var appGridConfigBuffer
    required property var appGridController

    title: i18nd("dev.xarbit.appgrid", "AppGrid Settings")
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 34
    minimumWidth: Kirigami.Units.gridUnit * 36
    minimumHeight: Kirigami.Units.gridUnit * 26
    visible: false

    // Bumped to force the Content bindings (which read through it) to re-read
    // appGridConfig after a bulk restore / load-defaults.
    property int revision: 0

    // Keys we buffer for Reset/Cancel (every key the pages can edit).
    readonly property var _editableKeys: [
        // General (icon / customButtonImage / menuLabel are the panel button's,
        // configured in the Plasma applet config, not here)
        "gridColumns", "gridRows", "iconSize", "sortMode", "categoryBarDisplay",
        "showCategoryBar", "startWithFavorites", "sortFavoritesAlphabetically",
        "showRecentApps", "useSystemCategories", "hideEmptyCategories",
        "openCategoryOnHover", "openOnActiveScreen", "verticalOffset",
        "terminalShell", "checkForUpdates",
        // Appearance / Animations
        "showDividers", "showScrollbars", "showTooltips", "showNewAppBadge",
        "iconShadow", "hoverHighlight", "independentTextSize", "reduceGridSpacing",
        "hideLabelsOnFavorites",
        "hideGridWhenEmpty", "hoverAnimation", "shakeOnOpen",
        // Search
        "searchAll", "useExtraRunners", "searchUsesFrecency", "searchShowsHidden",
        "searchInlineCompletion", "showSearchShortcuts",
        // Header Actions
        "headerActions", "showActionLabels", "hideMenuButtonLabel",
        // Hidden Apps
        "hiddenApps"
    ]

    // The live config as this window last saw it (captured on every sync/apply).
    // _apply writes back only the keys the user actually changed against this
    // baseline, so a concurrent launcher live-write is not clobbered (#4). The
    // value math lives in configbuffer.js (unit-tested in tst_ConfigBuffer.qml).
    property var _liveBaseline: ({})

    // True when the buffer differs from the live config in any editable key.
    // Reads both sides + revision so it re-evaluates on any change.
    readonly property bool dirty: {
        void win.revision   // re-check after a bulk copy
        return ConfigBuffer.isDirty(appGridConfigBuffer, appGridConfig, _editableKeys)
    }

    // True when the buffer already holds every key's default (Defaults disables).
    readonly property bool atDefaults: {
        void win.revision
        return ConfigBuffer.atDefaults(appGridConfigBuffer, _editableKeys, _emptyDefaults)
    }

    // Copy live -> buffer: the pages start from what is actually saved.
    // Called on open and on Reset (discard staged edits).
    function _syncFromLive() {
        win._liveBaseline = ConfigBuffer.syncFromLive(appGridConfigBuffer, appGridConfig, _editableKeys)
        win.revision++
    }

    // Keys whose KConfigXT default is empty/derived: kconfig_compiler emits no
    // public defaultXValue Q_PROPERTY for them (only a private _helper), so read
    // them from this table instead. Values mirror config/main.xml.
    readonly property var _emptyDefaults: ({
        "terminalShell": "",
        "hiddenApps": []
    })

    // Stage each property's default value in the buffer (Defaults). Not applied
    // to the launcher / persisted until Apply / OK, matching System Settings.
    function _loadDefaults() {
        ConfigBuffer.loadDefaults(appGridConfigBuffer, _editableKeys, _emptyDefaults)
        win.revision++
    }

    // Commit the buffer to the live config and persist. Only now does the
    // launcher see the change (its Connections re-sync) and the file save.
    //
    // Write back only the keys the user actually changed in this session
    // (buffer differs from the baseline captured at the last sync). A key the
    // user left untouched is NOT re-written, so a concurrent launcher live-write
    // — e.g. right-click "Hide Application" mutating hiddenApps while this window
    // is open — is preserved instead of clobbered by the stale buffer value (#4).
    // Then re-sync from the now-authoritative live config so the pages and
    // `dirty` reflect both the applied edits and any concurrent change.
    function _apply() {
        ConfigBuffer.applyChanged(appGridConfigBuffer, appGridConfig, win._liveBaseline, _editableKeys)
        appGridConfig.save()
        _syncFromLive()   // re-baseline + refresh `dirty` (now false)
    }

    Component.onCompleted: _syncFromLive()
    // Re-sync when the window is (re-)shown — the same window instance is reused
    // across opens (main.cpp caches the engine), and the launcher may have
    // mutated the live config in between (e.g. right-click "Hide Application").
    onVisibleChanged: if (visible) _syncFromLive()

    pageStack.initialPage: Kirigami.Page {
        padding: 0

        footer: QQC2.ToolBar {
            // System Settings / KRunner-style action row.
            // Button order mirrors System Settings / Plasma's own config dialog:
            // Reset, Defaults on the left; OK, Apply, Cancel on the right.
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18ndc("dev.xarbit.appgrid", "@action:button discard unsaved changes", "Reset")
                    icon.name: "edit-undo"
                    enabled: win.dirty
                    onClicked: win._syncFromLive()
                }
                QQC2.Button {
                    text: i18ndc("dev.xarbit.appgrid", "@action:button reset all settings to their defaults", "Defaults")
                    icon.name: "edit-reset"
                    enabled: !win.atDefaults
                    onClicked: win._loadDefaults()
                }
                Item { Layout.fillWidth: true }
                QQC2.Button {
                    text: i18ndc("dev.xarbit.appgrid", "@action:button apply and close", "OK")
                    icon.name: "dialog-ok"
                    onClicked: { if (win.dirty) win._apply(); win.close() }
                }
                QQC2.Button {
                    text: i18ndc("dev.xarbit.appgrid", "@action:button apply settings", "Apply")
                    icon.name: "dialog-ok-apply"
                    enabled: win.dirty
                    onClicked: win._apply()
                }
                QQC2.Button {
                    text: i18ndc("dev.xarbit.appgrid", "@action:button", "Cancel")
                    icon.name: "dialog-cancel"
                    onClicked: win.close()
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // -- Category sidebar --------------------------------------------
            QQC2.Pane {
                Layout.fillHeight: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                padding: 0
                Kirigami.Theme.colorSet: Kirigami.Theme.View
                Kirigami.Theme.inherit: false

                ListView {
                    id: sidebar
                    anchors.fill: parent
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    currentIndex: 0
                    keyNavigationEnabled: true
                    model: ListModel {
                        ListElement { label: "General";        iconName: "preferences-desktop-plasma" }
                        ListElement { label: "Appearance";     iconName: "preferences-desktop-theme-applications" }
                        ListElement { label: "Search";         iconName: "system-search" }
                        ListElement { label: "Header Actions"; iconName: "configure-toolbars" }
                        ListElement { label: "Hidden Apps";    iconName: "view-hidden" }
                    }
                    // Mirrors Plasma's plasmoid-config sidebar (ConfigCategoryDelegate):
                    // a medium icon over a centered, wrapping label, the style's own
                    // ItemDelegate highlight (no custom background) on the current row.
                    delegate: QQC2.ItemDelegate {
                        id: catDelegate
                        width: ListView.view.width
                        hoverEnabled: true
                        highlighted: ListView.isCurrentItem
                        onClicked: sidebar.currentIndex = index

                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: Kirigami.Units.iconSizes.medium
                                implicitHeight: Kirigami.Units.iconSizes.medium
                                source: model.iconName
                                selected: Window.active && (catDelegate.highlighted || catDelegate.pressed)
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.smallSpacing
                                Layout.rightMargin: Kirigami.Units.smallSpacing
                                text: i18nd("dev.xarbit.appgrid", model.label)
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                color: Window.active && (catDelegate.highlighted || catDelegate.pressed)
                                    ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                            }
                        }
                    }
                }
            }
            Kirigami.Separator { Layout.fillHeight: true }

            // -- Content -----------------------------------------------------
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: sidebar.currentIndex

                // ---- General ----
                QQC2.ScrollView {
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        ConfigGeneralContent {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            configuration: appGridConfigBuffer
                            isPanel: false
                            // The launcher button's icon + text label belong to
                            // the panel plasmoid, configured there — not here.
                            showButtonAppearance: false
                            formFactor: 0
                            location: 0
                            availableShells: appGridController.availableShells()
                            isUniversalBuild: appGridController.isUniversalBuild
                            defaultIcon: "dev.xarbit.appgrid"
                            revision: win.revision
                        }
                    }
                }

                // ---- Appearance ----
                QQC2.ScrollView {
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        ConfigAppearanceContent {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            configuration: appGridConfigBuffer
                            isPanel: false
                            revision: win.revision
                        }
                    }
                }

                // ---- Search ----
                QQC2.ScrollView {
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        ConfigSearchContent {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            configuration: appGridConfigBuffer
                            revision: win.revision
                        }
                    }
                }

                // ---- Header Actions ----
                QQC2.ScrollView {
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        ConfigHeaderActionsContent {
                            Layout.fillWidth: true
                            Layout.margins: Kirigami.Units.largeSpacing
                            configuration: appGridConfigBuffer
                            isUniversalBuild: appGridController.isUniversalBuild
                            revision: win.revision
                        }
                    }
                }

                // ---- Hidden Apps ----
                // Self-scrolling body, so it fills the stack page directly
                // (no outer ScrollView — it manages its own list view).
                Item {
                    ConfigHiddenAppsContent {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        configuration: appGridConfigBuffer
                        appsModel: appGridController.appsModel
                        revision: win.revision
                    }
                }
            }
        }
    }
}
