/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the General settings page. Hosts (the plasmoid's
    thin ConfigGeneral.qml wrapper and the daemon's ConfigWindow) inject the
    configuration object and the bits of context the page needs, then place
    this FormLayout inside their own scrollable page.

    Value-reading bindings depend on `revision` so a host can force a re-read
    of `configuration` after a revert / load-defaults — KConfigXT's read() /
    useDefaults() may not emit per-property NOTIFY signals.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

Kirigami.FormLayout {
    id: root

    // -- Injected context --------------------------------------------------
    property var configuration
    property bool isPanel: false
    property int formFactor: 0          // PlasmaCore.Types.FormFactor
    property int location: 0            // PlasmaCore.Types.Location (icon preview frame)
    property var availableShells: []    // string list of shell paths
    property bool isUniversalBuild: false
    property string defaultIcon: "dev.xarbit.appgrid"
    // The launcher button's icon + text label belong to the panel plasmoid. The
    // Plasma applet config edits them in `configuration` directly; the daemon's
    // settings window edits them on a separate object that round-trips to the
    // plasmoid over D-Bus, so they read/write `buttonConfiguration` (defaults to
    // `configuration` for the applet KCM). Shown only when a button exists (#191).
    property bool showButtonAppearance: true
    property var buttonConfiguration: configuration
    // Bumped by the host to force the value bindings below to re-read.
    property int revision: 0

    // Direct children of this one FormLayout (not a nested sub-form) so the
    // Icon: / Text label: rows share the page's label column and wide/wrap mode
    // with everything below them (#191).
    IconPickerButton {
        visible: root.showButtonAppearance
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon:")
        configuration: root.buttonConfiguration
        location: root.location
        defaultIcon: root.defaultIcon
        revision: root.revision
    }

    LauncherLabelField {
        visible: root.showButtonAppearance
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Text label:")
        configuration: root.buttonConfiguration
        formFactor: root.formFactor
        revision: root.revision
    }

    Item {
        visible: root.showButtonAppearance
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: gridColumns
        visible: !root.isPanel
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icons per row:")
        from: 3; to: 10
        value: (root.revision, root.configuration.gridColumns)
        onValueModified: root.configuration.gridColumns = value
    }
    QQC2.SpinBox {
        id: gridRows
        visible: !root.isPanel
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Visible rows:")
        from: 2; to: 10
        value: (root.revision, root.configuration.gridRows)
        onValueModified: root.configuration.gridRows = value
    }
    QQC2.ComboBox {
        id: iconSize
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Size:")
        model: [i18nd("dev.xarbit.appgrid", "Small"), i18nd("dev.xarbit.appgrid", "Medium"), i18nd("dev.xarbit.appgrid", "Large")]
        currentIndex: (root.revision, root.configuration.iconSize)
        onActivated: root.configuration.iconSize = currentIndex
    }
    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18nd("dev.xarbit.appgrid",
            "Drives icon size plus the surrounding content density: search field, category buttons, and search results scale together. Control buttons stay fixed.")
    }
    QQC2.ComboBox {
        id: sortMode
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Sort order:")
        model: [i18nd("dev.xarbit.appgrid", "Alphabetical"), i18nd("dev.xarbit.appgrid", "Most Used"), i18nd("dev.xarbit.appgrid", "By Category")]
        currentIndex: (root.revision, root.configuration.sortMode)
        onActivated: root.configuration.sortMode = currentIndex
    }
    QQC2.ComboBox {
        id: categoryBarDisplay
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Category tab style:")
        enabled: showCategoryBar.checked
        textRole: "text"
        valueRole: "value"
        // Values are stable enum ids (1 = legacy "Text only", folded into
        // Default now that the anchor tabs are always icon-only), so the
        // box maps by value rather than row index.
        model: [
            { value: 0, text: i18nd("dev.xarbit.appgrid", "Default") },
            { value: 2, text: i18nd("dev.xarbit.appgrid", "Icon and text") },
            { value: 3, text: i18nd("dev.xarbit.appgrid", "Icon only") },
        ]
        onActivated: root.configuration.categoryBarDisplay = currentValue
        // Install the currentIndex binding once the model is ready, so the
        // first evaluation can actually find the stored value (an inline
        // binding evaluates during creation before the model is assigned and
        // sticks at the fallback). Falls back to Default (0) for a value not
        // in the model — e.g. the dropped legacy "Text only" (1).
        Component.onCompleted: currentIndex = Qt.binding(function() {
            return Math.max(0, indexOfValue((root.revision, root.configuration.categoryBarDisplay)))
        })
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: showCategoryBar
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Behavior:")
        text: i18nd("dev.xarbit.appgrid", "Show category bar")
        checked: (root.revision, root.configuration.showCategoryBar)
        onToggled: root.configuration.showCategoryBar = checked
    }
    QQC2.CheckBox {
        id: startWithFavorites
        text: i18nd("dev.xarbit.appgrid", "Start with favorites tab")
        enabled: showCategoryBar.checked
        checked: (root.revision, root.configuration.startWithFavorites)
        onToggled: root.configuration.startWithFavorites = checked
    }
    QQC2.CheckBox {
        id: sortFavoritesAlphabetically
        text: i18nd("dev.xarbit.appgrid", "Sort favorites alphabetically")
        checked: (root.revision, root.configuration.sortFavoritesAlphabetically)
        onToggled: root.configuration.sortFavoritesAlphabetically = checked
    }
    QQC2.CheckBox {
        id: enableActivities
        text: i18nd("dev.xarbit.appgrid", "Scope favorites and folders per activity")
        checked: (root.revision, root.configuration.enableActivities)
        onToggled: root.configuration.enableActivities = checked
    }
    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18nd("dev.xarbit.appgrid",
            "Off keeps favorites and folders global. Turning it off later does not delete per-activity data, it just hides it until enabled again.")
    }
    QQC2.CheckBox {
        id: showRecentApps
        text: i18nd("dev.xarbit.appgrid", "Show recently used applications")
        enabled: sortMode.currentIndex !== 1 || startWithFavorites.checked
        checked: (root.revision, root.configuration.showRecentApps)
        onToggled: root.configuration.showRecentApps = checked
    }
    QQC2.CheckBox {
        id: useSystemCategories
        text: i18nd("dev.xarbit.appgrid", "Use system categories (supports KDE Menu Editor)")
        enabled: showCategoryBar.checked
        checked: (root.revision, root.configuration.useSystemCategories)
        onToggled: root.configuration.useSystemCategories = checked
    }
    QQC2.CheckBox {
        id: categoryFoldersEnabled
        text: i18nd("dev.xarbit.appgrid", "Group categories into folders")
        // Needs the kmenuedit hierarchy, which only exists in system categories.
        enabled: showCategoryBar.checked && useSystemCategories.checked
        checked: (root.revision, root.configuration.categoryFoldersEnabled)
        onToggled: root.configuration.categoryFoldersEnabled = checked
    }
    QQC2.CheckBox {
        id: hideEmptyCategories
        text: i18nd("dev.xarbit.appgrid", "Hide empty categories")
        enabled: showCategoryBar.checked
        checked: (root.revision, root.configuration.hideEmptyCategories)
        onToggled: root.configuration.hideEmptyCategories = checked
    }
    QQC2.CheckBox {
        id: openCategoryOnHover
        text: i18nd("dev.xarbit.appgrid", "Open categories on hover")
        enabled: showCategoryBar.checked
        checked: (root.revision, root.configuration.openCategoryOnHover)
        onToggled: root.configuration.openCategoryOnHover = checked
    }
    QQC2.CheckBox {
        id: openOnActiveScreen
        visible: !root.isPanel
        text: i18nd("dev.xarbit.appgrid", "Open on screen with mouse focus (otherwise on panel screen)")
        checked: (root.revision, root.configuration.openOnActiveScreen)
        onToggled: root.configuration.openOnActiveScreen = checked
    }

    Item {
        visible: !root.isPanel
        Kirigami.FormData.isSection: true
    }

    QQC2.Slider {
        id: verticalOffset
        visible: !root.isPanel
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Vertical position:")
        from: -100; to: 100; stepSize: 25
        snapMode: QQC2.Slider.SnapAlways
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        value: (root.revision, root.configuration.verticalOffset)
        onMoved: root.configuration.verticalOffset = value
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        id: terminalShell
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Terminal shell:")
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        model: {
            var shells = root.availableShells || []
            return [i18nd("dev.xarbit.appgrid", "Default (/bin/sh)")].concat(shells)
        }
        currentIndex: {
            root.revision // re-read trigger
            if (!root.configuration.terminalShell) return 0
            var shells = root.availableShells || []
            var idx = shells.indexOf(root.configuration.terminalShell)
            return idx >= 0 ? idx + 1 : 0
        }
        onActivated: function(index) {
            if (index === 0) {
                root.configuration.terminalShell = ""
            } else {
                var shells = root.availableShells || []
                root.configuration.terminalShell = shells[index - 1] || ""
            }
        }
    }

    Item {
        visible: root.isUniversalBuild === true
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: checkForUpdates
        visible: root.isUniversalBuild === true
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Updates:")
        text: i18nd("dev.xarbit.appgrid", "Check the AppGrid website for new releases")
        checked: (root.revision, root.configuration.checkForUpdates)
        onToggled: root.configuration.checkForUpdates = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Anonymous request once per day to %1. Shows an indicator near the session buttons when a new version is available; no automatic install.", "https://appgrid.xarbit.dev/api/latest.json")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
