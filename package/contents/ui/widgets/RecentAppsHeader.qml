/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Recently used apps header for the app grid view.
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../controllers"
import "../js/themecolors.js" as ThemeColors
import "../js/constants.js" as Const

Column {
    id: recentHeader

    property var appsModel: null
    property real cellWidth: 100
    property real cellHeight: 100
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Label font scale, following the size preset (Scale.textScale).
    property real fontScale: 1.0
    // Icon delegate config, injected from the boundary's ConfigCache.
    required property int hoverAnimation
    required property bool shadowEnabled
    property bool hoverHighlight: true
    property int currentRecentIndex: -1
    property bool gridHasFocus: false
    property bool favoritesActive: false
    property bool hideBottomLabel: false
    property bool showDividers: true
    property bool showTooltips: true
    // Shared DragSource from the plasmoid root so recent apps can also be
    // dragged out to external targets (taskbar, panel, Dolphin, desktop).
    property DragSource dragSource: null

    signal recentLaunched(string storageId)
    signal contextMenuRequested(string storageId, string desktopFile)
    signal shakeAll()

    // Consumer-provided modifier-click handler. Returns true if the click
    // was consumed (Ctrl/Shift+click extending the grid selection); false
    // for a plain click that should fall through to launch. The recents
    // row lives in indices 0 .. recentCount-1 of the unified selection
    // space, so the consumer passes the recent index straight through.
    property var tryModifierClick: function(recentIdx, mouse) { return false }

    // Live selection dictionary the consumer's SelectionState owns —
    // delegates index into it by storageId to drive the selection halo.
    property var selectionSids: ({})
    property bool multiSelectActive: false

    // Parallel URL / icon lists for the current selection, used by the
    // drag handler so dropping a recent that's part of a multi-selection
    // carries the full bundle to the target.
    property list<string> multiSelectionUrls: []
    property list<string> multiSelectionIcons: []

    spacing: Kirigami.Units.smallSpacing

    SectionLabel {
        leftPadding: Kirigami.Units.largeSpacing
        text: i18nd("dev.xarbit.appgrid", "Recently Used")
    }

    Flow {
        width: parent.width

        Repeater {
            model: recentHeader.appsModel ? recentHeader.appsModel.recentApps : []
            delegate: Item {
                id: recentDelegate
                required property string modelData
                required property int index
                readonly property var appData: recentHeader.appsModel ? recentHeader.appsModel.getByStorageId(modelData) : ({})
                width: recentHeader.cellWidth
                height: recentHeader.cellHeight
                visible: appData.name !== undefined

                Rectangle {
                    anchors.centerIn: parent
                    width: recentHeader.cellWidth - Kirigami.Units.smallSpacing * 2
                    height: recentHeader.cellHeight - Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.cornerRadius
                    color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.2)
                    border.width: 1
                    border.color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.6)
                    visible: recentHeader.currentRecentIndex === recentDelegate.index && recentHeader.gridHasFocus
                }

                AppIconDelegate {
                    id: recentIcon
                    anchors.fill: parent
                    fontScale: recentHeader.fontScale
                    appName: recentDelegate.appData.name || ""
                    appIcon: recentDelegate.appData.iconName || Const.DEFAULT_ICON
                    iconGeneration: recentHeader.appsModel ? recentHeader.appsModel.iconGeneration : 0
                    appGenericName: recentDelegate.appData.genericName || ""
                    appComment: recentDelegate.appData.comment || ""
                    installSource: recentDelegate.appData.installSource || ""
                    showTooltip: recentHeader.showTooltips
                    isCurrentItem: recentHeader.currentRecentIndex === recentDelegate.index
                    iconSize: recentHeader.iconSize
                    hoverAnimation: recentHeader.hoverAnimation
                    shadowEnabled: recentHeader.shadowEnabled
                    hoverHighlight: recentHeader.hoverHighlight
                    storageId: recentDelegate.modelData
                    desktopFile: recentDelegate.appData.desktopFile || ""
                    dragSource: recentHeader.dragSource
                    selected: recentHeader.multiSelectActive
                              && !!recentHeader.selectionSids[recentDelegate.modelData]
                    multiSelectionSids: selected
                        ? Object.keys(recentHeader.selectionSids).filter(function(k) {
                              return recentHeader.selectionSids[k]
                          })
                        : []
                    multiSelectionUrls: selected ? recentHeader.multiSelectionUrls : []
                    multiSelectionIcons: selected ? recentHeader.multiSelectionIcons : []
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            recentHeader.contextMenuRequested(recentDelegate.modelData, recentDelegate.appData.desktopFile || "")
                            return
                        }
                        if (recentHeader.tryModifierClick(recentDelegate.index, mouse))
                            return
                        recentHeader.recentLaunched(recentDelegate.modelData)
                    }
                }

                Connections {
                    target: recentHeader
                    function onShakeAll() { recentIcon.shake() }
                }
            }
        }
    }

    HorizontalDivider {
        width: parent.width
        opacity: recentHeader.showDividers ? 1 : 0
    }

    SectionLabel {
        visible: !recentHeader.hideBottomLabel
        leftPadding: Kirigami.Units.largeSpacing
        text: recentHeader.favoritesActive
              ? i18nd("dev.xarbit.appgrid", "Favorites")
              : i18nd("dev.xarbit.appgrid", "All Apps")
    }

    Item { width: 1; height: Kirigami.Units.smallSpacing }
}
