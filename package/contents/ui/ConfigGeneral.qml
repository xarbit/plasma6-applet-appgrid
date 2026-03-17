/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.draganddrop as DragDrop
import org.kde.iconthemes as KIconThemes
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

KCMUtils.SimpleKCM {
    id: configGeneral

    // --- Config bindings (cfg_ prefix is required by Plasma KCM framework) ---
    property string cfg_icon: Plasmoid.configuration.icon
    property bool cfg_useCustomButtonImage: Plasmoid.configuration.useCustomButtonImage
    property string cfg_customButtonImage: Plasmoid.configuration.customButtonImage
    property alias cfg_gridColumns: gridColumns.value
    property alias cfg_gridRows: gridRows.value
    property alias cfg_iconSize: iconSize.currentIndex
    property alias cfg_sortMode: sortMode.currentIndex
    property alias cfg_overrideRadius: overrideRadius.checked
    property alias cfg_cornerRadius: cornerRadius.value
    property alias cfg_showDividers: showDividers.checked
    property alias cfg_showScrollbars: showScrollbars.checked
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_enableBlur: enableBlur.checked
    property alias cfg_openOnActiveScreen: openOnActiveScreen.checked
    property alias cfg_showCategoryBar: showCategoryBar.checked
    property alias cfg_searchAll: searchAll.checked
    property alias cfg_startWithFavorites: startWithFavorites.checked
    property alias cfg_shakeOnOpen: shakeOnOpen.checked
    property alias cfg_hoverAnimation: hoverAnimation.currentIndex
    property alias cfg_showActionLabels: showActionLabels.checked
    property alias cfg_showRecentApps: showRecentApps.checked
    property alias cfg_useExtraRunners: useExtraRunners.checked
    property alias cfg_useSystemCategories: useSystemCategories.checked
    property string cfg_terminalShell: Plasmoid.configuration.terminalShell
    property var cfg_hiddenApps: Plasmoid.configuration.hiddenApps

    // Default icon defined in main.xml — single source of truth for fallback.
    readonly property string defaultIcon: "start-here-kde-symbolic"

    // ListModel mirror for cfg_hiddenApps (StringList doesn't work directly as Repeater model).
    ListModel { id: hiddenAppsModel }
    Component.onCompleted: syncHiddenModel()
    onCfg_hiddenAppsChanged: syncHiddenModel()

    function syncHiddenModel() {
        hiddenAppsModel.clear()
        var apps = cfg_hiddenApps
        if (apps && apps.length) {
            for (var i = 0; i < apps.length; i++) {
                if (apps[i] !== "")
                    hiddenAppsModel.append({ storageId: apps[i] })
            }
        }
    }

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        // --- Icon picker ---

        QQC2.Button {
            id: iconButton
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon:")
            implicitWidth: previewFrame.width + Kirigami.Units.smallSpacing * 2
            implicitHeight: previewFrame.height + Kirigami.Units.smallSpacing * 2
            checkable: true
            checked: dropArea.containsAcceptableDrag
            onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.open()

            DragDrop.DropArea {
                id: dropArea
                property bool containsAcceptableDrag: false
                anchors.fill: parent

                onDragEnter: event => {
                    const urlString = event.mimeData.url.toString();
                    const extensions = [".png", ".xpm", ".svg", ".svgz"];
                    containsAcceptableDrag = urlString.startsWith("file:///")
                        && extensions.some(ext => urlString.endsWith(ext));
                    if (!containsAcceptableDrag) event.ignore();
                }
                onDragLeave: containsAcceptableDrag = false
                onDrop: event => {
                    if (containsAcceptableDrag)
                        iconDialog.setCustomButtonImage(event.mimeData.url.toString().substr("file://".length));
                    containsAcceptableDrag = false;
                }
            }

            KIconThemes.IconDialog {
                id: iconDialog
                function setCustomButtonImage(image) {
                    configGeneral.cfg_customButtonImage = image || configGeneral.cfg_icon || configGeneral.defaultIcon
                    configGeneral.cfg_useCustomButtonImage = true;
                }
                onIconNameChanged: iconName => setCustomButtonImage(iconName)
            }

            KSvg.FrameSvgItem {
                id: previewFrame
                anchors.centerIn: parent
                imagePath: Plasmoid.location === PlasmaCore.Types.Vertical
                           || Plasmoid.location === PlasmaCore.Types.Horizontal
                           ? "widgets/panel-background" : "widgets/background"
                width: Kirigami.Units.iconSizes.large + fixedMargins.left + fixedMargins.right
                height: Kirigami.Units.iconSizes.large + fixedMargins.top + fixedMargins.bottom

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.large
                    height: width
                    source: configGeneral.cfg_useCustomButtonImage
                            ? configGeneral.cfg_customButtonImage
                            : configGeneral.cfg_icon
                }
            }

            QQC2.Menu {
                id: iconMenu
                y: parent.height
                onClosed: iconButton.checked = false

                QQC2.MenuItem {
                    text: i18ndc("dev.xarbit.appgrid", "@item:inmenu Open icon chooser dialog", "Choose\u2026")
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                QQC2.MenuItem {
                    text: i18ndc("dev.xarbit.appgrid", "@item:inmenu Reset icon to default", "Clear Icon")
                    icon.name: "edit-clear"
                    onClicked: {
                        configGeneral.cfg_icon = configGeneral.defaultIcon
                        configGeneral.cfg_customButtonImage = ""
                        configGeneral.cfg_useCustomButtonImage = false
                    }
                }
            }
        }

        // --- Grid size ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: gridColumns
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icons per row:")
            from: 3; to: 10
        }

        QQC2.SpinBox {
            id: gridRows
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Visible rows:")
            from: 2; to: 10
        }

        QQC2.ComboBox {
            id: iconSize
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon size:")
            model: [i18nd("dev.xarbit.appgrid", "Small"), i18nd("dev.xarbit.appgrid", "Medium"), i18nd("dev.xarbit.appgrid", "Large")]
        }

        RowLayout {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Sort order:")
            spacing: Kirigami.Units.largeSpacing

            QQC2.ComboBox {
                id: sortMode
                model: [i18nd("dev.xarbit.appgrid", "Alphabetical"), i18nd("dev.xarbit.appgrid", "Most Used")]
            }

            QQC2.CheckBox {
                id: showRecentApps
                text: i18nd("dev.xarbit.appgrid", "Show recently used applications")
                enabled: sortMode.currentIndex === 0
            }
        }

        // --- Appearance ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showCategoryBar
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Behavior:")
            text: i18nd("dev.xarbit.appgrid", "Show category bar")
        }

        QQC2.CheckBox {
            id: openOnActiveScreen
            text: i18nd("dev.xarbit.appgrid", "Open on screen with mouse focus (otherwise on panel screen)")
        }

        QQC2.CheckBox {
            id: searchAll
            text: i18nd("dev.xarbit.appgrid", "Search all apps regardless of active tab")
        }

        QQC2.CheckBox {
            id: startWithFavorites
            text: i18nd("dev.xarbit.appgrid", "Start with favorites tab")
            enabled: showCategoryBar.checked
        }

        QQC2.CheckBox {
            id: useSystemCategories
            text: i18nd("dev.xarbit.appgrid", "Use system categories (supports KDE Menu Editor)")
            enabled: showCategoryBar.checked
        }

        QQC2.ComboBox {
            id: terminalShell
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Terminal shell:")
            Layout.fillWidth: true
            model: {
                var shells = Plasmoid.availableShells ? Plasmoid.availableShells() : []
                return [i18nd("dev.xarbit.appgrid", "Default (/bin/sh)")].concat(shells)
            }
            currentIndex: {
                if (!configGeneral.cfg_terminalShell) return 0
                var shells = Plasmoid.availableShells ? Plasmoid.availableShells() : []
                var idx = shells.indexOf(configGeneral.cfg_terminalShell)
                return idx >= 0 ? idx + 1 : 0
            }
            onActivated: function(index) {
                if (index === 0)
                    configGeneral.cfg_terminalShell = ""
                else {
                    var shells = Plasmoid.availableShells ? Plasmoid.availableShells() : []
                    configGeneral.cfg_terminalShell = shells[index - 1] || ""
                }
            }
        }

        QQC2.CheckBox {
            id: showDividers
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Appearance:")
            text: i18nd("dev.xarbit.appgrid", "Show divider lines")
        }

        QQC2.CheckBox {
            id: showScrollbars
            text: i18nd("dev.xarbit.appgrid", "Show scrollbars")
        }

        QQC2.CheckBox {
            id: enableBlur
            text: i18nd("dev.xarbit.appgrid", "Enable background blur")
        }

        QQC2.ComboBox {
            id: hoverAnimation
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon animation:")
            model: [i18nd("dev.xarbit.appgrid", "None"), i18nd("dev.xarbit.appgrid", "Shake"), i18nd("dev.xarbit.appgrid", "Grow"), i18nd("dev.xarbit.appgrid", "Bounce"), i18nd("dev.xarbit.appgrid", "Spin"), i18nd("dev.xarbit.appgrid", "Shuffle")]
        }

        QQC2.CheckBox {
            id: shakeOnOpen
            text: i18nd("dev.xarbit.appgrid", "Animate icons on open")
            enabled: hoverAnimation.currentIndex > 0
        }

        QQC2.CheckBox {
            id: showActionLabels
            text: i18nd("dev.xarbit.appgrid", "Show labels on power/session buttons")
        }

        QQC2.CheckBox {
            id: useExtraRunners
            text: i18nd("dev.xarbit.appgrid", "Expand search to bookmarks, files, and websites")
        }

        QQC2.Button {
            text: i18nd("dev.xarbit.appgrid", "Configure Search Plugins…")
            icon.name: "settings-configure"
            enabled: useExtraRunners.checked
            onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_plasmasearch")
        }

        RowLayout {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Background opacity:")

            QQC2.Slider {
                id: backgroundOpacity
                from: 10; to: 100; stepSize: 5
                Layout.fillWidth: true
            }

            QQC2.Label {
                text: Math.round(backgroundOpacity.value) + "%"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            }
        }

        QQC2.CheckBox {
            id: overrideRadius
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Corner radius:")
            text: i18nd("dev.xarbit.appgrid", "Use custom corner radius")
        }

        RowLayout {
            enabled: overrideRadius.checked

            QQC2.SpinBox {
                id: cornerRadius
                from: 0; to: 60
            }

            QQC2.Label {
                text: i18nd("dev.xarbit.appgrid", "px")
                opacity: overrideRadius.checked ? 1.0 : 0.5
            }
        }

        // --- Reset ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.Button {
            Kirigami.FormData.label: ""
            icon.name: "edit-undo"
            text: i18nd("dev.xarbit.appgrid", "Reset to Defaults")
            onClicked: {
                configGeneral.cfg_icon = "start-here-kde-symbolic"
                configGeneral.cfg_useCustomButtonImage = false
                configGeneral.cfg_customButtonImage = ""
                gridColumns.value = 7
                gridRows.value = 4
                iconSize.currentIndex = 2
                sortMode.currentIndex = 1
                overrideRadius.checked = false
                cornerRadius.value = 24
                showDividers.checked = true
                showScrollbars.checked = false
                backgroundOpacity.value = 85
                enableBlur.checked = true
                openOnActiveScreen.checked = true
                showCategoryBar.checked = true
                searchAll.checked = true
                startWithFavorites.checked = false
                shakeOnOpen.checked = true
                hoverAnimation.currentIndex = 1
                showActionLabels.checked = false
                showRecentApps.checked = true
                useExtraRunners.checked = true
                useSystemCategories.checked = false
                configGeneral.cfg_terminalShell = ""
                terminalShell.currentIndex = 0
            }
        }

        // --- Hidden applications ---

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Hidden Applications")
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18nd("dev.xarbit.appgrid", "Right-click any application in the grid and choose \"Hide Application\" to add it here.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            visible: hiddenAppsModel.count === 0
            text: i18nd("dev.xarbit.appgrid", "No hidden applications.")
            opacity: 0.5
        }

        Repeater {
            model: hiddenAppsModel

            delegate: QQC2.ItemDelegate {
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                required property string storageId
                required property int index

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                        source: "application-x-executable"
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: storageId
                        elide: Text.ElideRight
                    }

                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove"
                        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Unhide")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: {
                            var list = configGeneral.cfg_hiddenApps.slice()
                            list.splice(index, 1)
                            configGeneral.cfg_hiddenApps = list
                        }
                    }
                }
            }
        }
    }
}
