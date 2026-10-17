/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The main app grid (All, a category or the favourites) with what surrounds
    it on the favourites tab: the back bar while inside a favourites folder
    (folders drill in place, #18), the loading state while KActivities starts,
    and the overlay the icon shuffle animates on.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../controllers"
import "../widgets"

ColumnLayout {
    id: pane

    // The panel's ConfigCache: the grid's look and behaviour settings.
    required property var cfg
    // The model the grid shows: the grouped favourites, or the app model.
    property var model: null
    property var appsModel: null
    property var sharedFavoritesModel: null
    property var favoritesGroupedModel: null
    property var favoritesManager: null
    property int favoriteIdRole: -1
    property var dragSource: null
    property var searchField: null
    property bool favoritesActive: false
    property int columns: 5
    // How the cells draw (CellStyle).
    required property CellStyle cellStyle

    readonly property alias grid: appGrid
    // Inside a favourites folder: Esc climbs out rather than closing.
    readonly property bool folderOpen: favoritesActive && nav.canGoBack

    signal launched(int index)
    signal recentLaunched(string storageId)
    signal bulkLaunchRequested(var sids)
    signal categoryNavRequested(int direction)
    signal contextMenuRequested(string storageId, string desktopFile, var selectedSids)
    signal folderContextMenuRequested(string folderId)
    signal emptyAreaContextMenuRequested()

    // Back to the just-opened state: the grid's scroll, cursor and
    // selection, and the folder navigation's memory.
    function reset() {
        appGrid.resetView()
        nav.reset()
    }

    spacing: Kirigami.Units.smallSpacing

    // The same drill navigation the menu folders use, so going in and out of a
    // folder moves the selection the same way.
    DrillNavigator {
        id: nav
        model: pane.favoritesGroupedModel
        grid: appGrid
        active: pane.favoritesActive
    }

    // Back + breadcrumb while inside a favourites folder; drag a member onto it
    // to remove it from the folder.
    DrillBar {
        Layout.fillWidth: true
        model: pane.favoritesGroupedModel
        dragSource: pane.dragSource
        editable: true
        visible: pane.folderOpen
        onRemoveMemberRequested: function(sid) {
            if (pane.favoritesGroupedModel)
                pane.favoritesGroupedModel.removeFromFolder(pane.favoritesGroupedModel.currentPath, sid)
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Favourites come from KActivities, which may still be starting on a
        // cold boot; show a loading state instead of an empty grid until the
        // store is ready.
        Kirigami.LoadingPlaceholder {
            anchors.centerIn: parent
            z: 1
            visible: pane.favoritesActive && !!pane.sharedFavoritesModel
                     && !pane.sharedFavoritesModel.enabled
        }

        AppGridView {
            id: appGrid
            anchors.fill: parent
            model: pane.model
            appsModel: pane.appsModel
            sharedFavoritesModel: pane.sharedFavoritesModel
            favoritesGroupedModel: pane.favoritesGroupedModel
            // Editable here (unlike the read-only menu tree).
            groupedModel: pane.favoritesGroupedModel
            favoritesManager: pane.favoritesManager
            favoriteIdRole: pane.favoriteIdRole
            dragSource: pane.dragSource
            searchField: pane.searchField
            columns: pane.columns
            adaptiveColumns: true
            cellStyle: pane.cellStyle
            sortFavoritesAlphabetically: pane.cfg.sortFavoritesAlphabetically
            showRecentApps: pane.cfg.showRecentApps
            startWithFavorites: pane.cfg.startWithFavorites
            favoritesActive: pane.favoritesActive
            hideLabelsOnFavorites: pane.cfg.hideLabelsOnFavorites
            shuffleOverlayParent: shuffleOverlay

            // Folders drill in place; Esc climbs back out (the window Shortcut
            // yields via folderOpen, like the menu view).
            onOpenFolderRequested: function(folderId) {
                if (pane.favoritesGroupedModel)
                    pane.favoritesGroupedModel.enterFolder(folderId)
            }
            onEscapePressed: nav.goBack()
            onFolderContextMenuRequested: folderId => pane.folderContextMenuRequested(folderId)
            onEmptyAreaContextMenuRequested: pane.emptyAreaContextMenuRequested()
            onLaunched: index => pane.launched(index)
            onRecentLaunched: storageId => pane.recentLaunched(storageId)
            onBulkLaunchRequested: sids => pane.bulkLaunchRequested(sids)
            onCategoryNavRequested: direction => pane.categoryNavRequested(direction)
            // The whole live selection goes along: the menu derives both its
            // selection toggle and its bulk counts from it.
            onContextMenuRequested: (index, storageId, desktopFile) =>
                pane.contextMenuRequested(storageId, desktopFile, appGrid.selection.sidList())
            onShuffleAnimRequested: function(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex) {
                shuffleOverlay.startAnim(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex)
            }
        }

        ShuffleOverlay {
            id: shuffleOverlay
            anchors.fill: parent
            z: 10
            iconSize: pane.cellStyle.iconSize
            onSwapFinished: function(fromIndex, toIndex, fromIcon, toIcon) {
                appGrid.applySwap(fromIndex, toIndex, fromIcon, toIcon)
            }
        }
    }
}
