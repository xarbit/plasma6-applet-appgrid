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

    property string cfg_icon: Plasmoid.configuration.icon
    property bool cfg_useCustomButtonImage: Plasmoid.configuration.useCustomButtonImage
    property string cfg_customButtonImage: Plasmoid.configuration.customButtonImage
    property alias cfg_iconSize: iconSize.currentIndex
    property alias cfg_sortMode: sortMode.currentIndex
    property alias cfg_showDividers: showDividers.checked
    property alias cfg_showScrollbars: showScrollbars.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showNewAppBadge: showNewAppBadge.checked
    property alias cfg_hideLabelsOnFavorites: hideLabelsOnFavorites.checked
    property alias cfg_showCategoryBar: showCategoryBar.checked
    property alias cfg_searchAll: searchAll.checked
    property alias cfg_startWithFavorites: startWithFavorites.checked
    property alias cfg_shakeOnOpen: shakeOnOpen.checked
    property alias cfg_hoverAnimation: hoverAnimation.currentIndex
    property alias cfg_showSessionButtons: showSessionButtons.checked
    property alias cfg_showActionLabels: showActionLabels.checked
    property alias cfg_showRecentApps: showRecentApps.checked
    property alias cfg_useExtraRunners: useExtraRunners.checked
    property alias cfg_useSystemCategories: useSystemCategories.checked
    property alias cfg_hideEmptyCategories: hideEmptyCategories.checked
    property string cfg_menuLabel: Plasmoid.configuration.menuLabel
    property string cfg_terminalShell: Plasmoid.configuration.terminalShell
    property var cfg_hiddenApps: Plasmoid.configuration.hiddenApps

    readonly property string defaultIcon: "start-here-kde-symbolic"

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

        Kirigami.ActionTextField {
            id: menuLabel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Text label:")
            Layout.fillWidth: true
            placeholderText: i18nd("dev.xarbit.appgrid", "Type here to add a text label")
            text: configGeneral.cfg_menuLabel
            onTextChanged: configGeneral.cfg_menuLabel = text
            enabled: Plasmoid.formFactor !== PlasmaCore.Types.Vertical
            rightActions: Kirigami.Action {
                icon.name: "edit-clear"
                visible: menuLabel.text.length > 0
                onTriggered: configGeneral.cfg_menuLabel = ""
            }
        }

        // --- Grid size ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            id: iconSize
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon size:")
            model: [i18nd("dev.xarbit.appgrid", "Small"), i18nd("dev.xarbit.appgrid", "Medium"), i18nd("dev.xarbit.appgrid", "Large")]
        }

        QQC2.ComboBox {
            id: sortMode
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Sort order:")
            model: [i18nd("dev.xarbit.appgrid", "Alphabetical"), i18nd("dev.xarbit.appgrid", "Most Used"), i18nd("dev.xarbit.appgrid", "By Category")]
        }

        // --- Appearance ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showCategoryBar
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Behavior:")
            text: i18nd("dev.xarbit.appgrid", "Show category bar")
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
            id: showRecentApps
            text: i18nd("dev.xarbit.appgrid", "Show recently used applications")
            enabled: sortMode.currentIndex !== 1 || startWithFavorites.checked
        }

        QQC2.CheckBox {
            id: useSystemCategories
            text: i18nd("dev.xarbit.appgrid", "Use system categories (supports KDE Menu Editor)")
            enabled: showCategoryBar.checked
        }

        QQC2.CheckBox {
            id: hideEmptyCategories
            text: i18nd("dev.xarbit.appgrid", "Hide empty categories")
            enabled: showCategoryBar.checked
        }

        QQC2.CheckBox {
            id: useExtraRunners
            text: i18nd("dev.xarbit.appgrid", "Expand search to bookmarks, files, and websites")
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
            id: showTooltips
            text: i18nd("dev.xarbit.appgrid", "Show tooltips on hover")
        }

        QQC2.CheckBox {
            id: showNewAppBadge
            text: i18nd("dev.xarbit.appgrid", "Show new app badge")
        }

        QQC2.CheckBox {
            id: hideLabelsOnFavorites
            text: i18nd("dev.xarbit.appgrid", "Hide app labels on favorites tab")
            enabled: showCategoryBar.checked
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
            id: showSessionButtons
            text: i18nd("dev.xarbit.appgrid", "Show power/session buttons")
        }

        QQC2.CheckBox {
            id: showActionLabels
            text: i18nd("dev.xarbit.appgrid", "Show labels on power/session buttons")
            enabled: showSessionButtons.checked
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
                configGeneral.cfg_menuLabel = ""
                iconSize.currentIndex = 2
                sortMode.currentIndex = 1
                showDividers.checked = false
                showScrollbars.checked = false
                showTooltips.checked = true
                showNewAppBadge.checked = true
                hideLabelsOnFavorites.checked = false
                showCategoryBar.checked = true
                searchAll.checked = true
                startWithFavorites.checked = false
                showRecentApps.checked = true
                hideEmptyCategories.checked = true
                shakeOnOpen.checked = true
                hoverAnimation.currentIndex = 1
                showSessionButtons.checked = true
                showActionLabels.checked = false
                useExtraRunners.checked = true
                useSystemCategories.checked = false
                hideEmptyCategories.checked = true
                configGeneral.cfg_terminalShell = ""
                terminalShell.currentIndex = 0
            }
        }

        // --- Hidden applications ---

        Item { Kirigami.FormData.isSection: true }

        ColumnLayout {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Hidden apps:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18nd("dev.xarbit.appgrid", "Right-click any app in the grid to hide it, or type h: in the search bar.")
                font: Kirigami.Theme.smallFont
                opacity: 0.5
            }

            QQC2.Label {
                visible: hiddenAppsModel.count === 0
                text: i18nd("dev.xarbit.appgrid", "No hidden applications.")
                opacity: 0.5
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            Repeater {
                model: hiddenAppsModel

                delegate: QQC2.ItemDelegate {
                    Layout.fillWidth: true
                    required property string storageId
                    required property int index

                    property var appInfo: Plasmoid.appsModel.getByStorageId(storageId) || ({})

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            implicitWidth: Kirigami.Units.iconSizes.smallMedium
                            implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            source: appInfo.iconName || "application-x-executable"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QQC2.Label {
                                Layout.fillWidth: true
                                text: appInfo.name || storageId
                                elide: Text.ElideRight
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                visible: !!appInfo.name
                                text: storageId
                                font: Kirigami.Theme.smallFont
                                opacity: 0.4
                                elide: Text.ElideRight
                            }
                        }

                        QQC2.ToolButton {
                            icon.name: "view-visible"
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

            QQC2.Button {
                visible: hiddenAppsModel.count > 0
                Layout.topMargin: Kirigami.Units.smallSpacing
                icon.name: "edit-undo"
                text: i18nd("dev.xarbit.appgrid", "Unhide All")
                onClicked: configGeneral.cfg_hiddenApps = []
            }
        }
    }
}
