/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Recently used apps header for the app grid view.
*/

import QtQuick
import dev.xarbit.appgrid.models
import org.kde.kirigami as Kirigami

import "../controllers"
import "../js/constants.js" as Const

Column {
    id: recentHeader

    property var appsModel: null
    // The controller's LaunchStateStore: the recents come from it.
    property var launchState: null
    property real cellWidth: 100
    property real cellHeight: 100
    // How the cells draw (CellStyle).
    required property CellStyle cellStyle
    property int currentRecentIndex: -1
    property bool gridHasFocus: false
    property bool favoritesActive: false
    property bool hideBottomLabel: false
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
            model: RecentAppsModel {
                launchState: recentHeader.launchState
            }
            delegate: Item {
                id: recentDelegate
                required property int index
                required property string storageId
                required property string name
                required property string iconName
                required property string genericName
                required property string comment
                required property string installSource
                required property string desktopFile
                width: recentHeader.cellWidth
                height: recentHeader.cellHeight
                // An app that is no longer installed keeps its place, unseen.
                visible: name !== ""

                GridHighlight {
                    cellWidth: recentHeader.cellWidth
                    cellHeight: recentHeader.cellHeight
                    visible: recentHeader.currentRecentIndex === recentDelegate.index && recentHeader.gridHasFocus
                }

                AppIconDelegate {
                    id: recentIcon
                    anchors.fill: parent
                    appName: recentDelegate.name
                    appIcon: recentDelegate.iconName || Const.DEFAULT_ICON
                    iconGeneration: recentHeader.appsModel ? recentHeader.appsModel.iconGeneration : 0
                    appGenericName: recentDelegate.genericName
                    appComment: recentDelegate.comment
                    installSource: recentDelegate.installSource
                    isCurrentItem: recentHeader.currentRecentIndex === recentDelegate.index
                    cellStyle: recentHeader.cellStyle
                    storageId: recentDelegate.storageId
                    desktopFile: recentDelegate.desktopFile
                    dragSource: recentHeader.dragSource
                    selected: recentHeader.multiSelectActive
                              && !!recentHeader.selectionSids[recentDelegate.storageId]
                    multiSelectionSids: selected
                        ? Object.keys(recentHeader.selectionSids).filter(function(k) {
                              return recentHeader.selectionSids[k]
                          })
                        : []
                    multiSelectionUrls: selected ? recentHeader.multiSelectionUrls : []
                    multiSelectionIcons: selected ? recentHeader.multiSelectionIcons : []
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            recentHeader.contextMenuRequested(recentDelegate.storageId, recentDelegate.desktopFile)
                            return
                        }
                        if (recentHeader.tryModifierClick(recentDelegate.index, mouse))
                            return
                        recentHeader.recentLaunched(recentDelegate.storageId)
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
        opacity: recentHeader.cellStyle.showDividers ? 1 : 0
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
