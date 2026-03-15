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
    property alias cfg_gridColumns: gridColumns.value
    property alias cfg_gridRows: gridRows.value
    property alias cfg_iconSize: iconSize.currentIndex
    property alias cfg_sortMode: sortMode.currentIndex
    property alias cfg_showScrollbars: showScrollbars.checked
    property alias cfg_searchAll: searchAll.checked
    property alias cfg_startWithFavorites: startWithFavorites.checked
    property alias cfg_shakeOnOpen: shakeOnOpen.checked
    property alias cfg_hoverAnimation: hoverAnimation.currentIndex
    property alias cfg_showActionLabels: showActionLabels.checked
    property alias cfg_showRecentApps: showRecentApps.checked
    property alias cfg_useExtraRunners: useExtraRunners.checked
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
            Kirigami.FormData.label: i18n("Icon:")
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
                    text: i18nc("@item:inmenu Open icon chooser dialog", "Choose\u2026")
                    icon.name: "document-open-folder"
                    onClicked: iconDialog.open()
                }
                QQC2.MenuItem {
                    text: i18nc("@item:inmenu Reset icon to default", "Clear Icon")
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
            Kirigami.FormData.label: i18n("Icons per row:")
            from: 3; to: 10
        }

        QQC2.SpinBox {
            id: gridRows
            Kirigami.FormData.label: i18n("Visible rows:")
            from: 2; to: 10
        }

        QQC2.ComboBox {
            id: iconSize
            Kirigami.FormData.label: i18n("Icon size:")
            model: [i18n("Small"), i18n("Medium"), i18n("Large")]
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Sort order:")
            spacing: Kirigami.Units.largeSpacing

            QQC2.ComboBox {
                id: sortMode
                model: [i18n("Alphabetical"), i18n("Most Used")]
            }

            QQC2.CheckBox {
                id: showRecentApps
                text: i18n("Show recently used applications")
                enabled: sortMode.currentIndex === 0
            }
        }

        // --- Appearance ---

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: searchAll
            Kirigami.FormData.label: i18n("Behavior:")
            text: i18n("Search all apps regardless of active tab")
        }

        QQC2.CheckBox {
            id: startWithFavorites
            text: i18n("Start with favorites tab")
        }

        QQC2.CheckBox {
            id: showScrollbars
            Kirigami.FormData.label: i18n("Appearance:")
            text: i18n("Show scrollbars")
        }

        QQC2.ComboBox {
            id: hoverAnimation
            Kirigami.FormData.label: i18n("Icon animation:")
            model: [i18n("None"), i18n("Shake"), i18n("Grow"), i18n("Bounce"), i18n("Spin")]
        }

        QQC2.CheckBox {
            id: shakeOnOpen
            text: i18n("Animate icons on open")
            enabled: hoverAnimation.currentIndex > 0
        }

        QQC2.CheckBox {
            id: showActionLabels
            text: i18n("Show labels on power/session buttons")
        }

        QQC2.CheckBox {
            id: useExtraRunners
            text: i18n("Expand search to bookmarks, files, and websites")
        }

        QQC2.Button {
            text: i18n("Configure Search Plugins…")
            icon.name: "settings-configure"
            enabled: useExtraRunners.checked
            onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_plasmasearch")
        }

        // --- Hidden applications ---

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Hidden Applications")
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("Right-click any application in the grid and choose \"Hide Application\" to add it here.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            visible: hiddenAppsModel.count === 0
            text: i18n("No hidden applications.")
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
                        QQC2.ToolTip.text: i18n("Unhide")
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
