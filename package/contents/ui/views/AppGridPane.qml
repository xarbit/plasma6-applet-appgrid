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
    // The panel this pane lives in (GridHost), handed to its grid.
    required property GridHost host
    readonly property var sharedFavoritesModel: host.favoritesManager ? host.favoritesManager.sharedFavoritesModel : null
    readonly property var favoritesGroupedModel: host.favoritesManager ? host.favoritesManager.favoritesGroupedModel : null
    property bool favoritesActive: false

    readonly property alias grid: appGrid
    // Inside a favourites folder: Esc climbs out rather than closing.
    readonly property bool folderOpen: favoritesActive && nav.canGoBack

    signal folderContextMenuRequested(string folderId)
    signal emptyAreaContextMenuRequested()

    // Back to the just-opened state: out of any favourites folder (#18), and
    // the grid's scroll, cursor and selection and the navigation's memory.
    function reset() {
        if (favoritesGroupedModel)
            favoritesGroupedModel.resetToRoot()
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
        dragSource: pane.host.dragSource
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
            host: pane.host
            model: pane.model
            // Editable here (unlike the read-only menu tree).
            groupedModel: pane.favoritesGroupedModel
            adaptiveColumns: true
            // The shuffle animation's icons fly across the overlay.
            shuffle.overlay: shuffleOverlay
            sortFavoritesAlphabetically: pane.cfg.sortFavoritesAlphabetically
            showRecentApps: pane.cfg.showRecentApps
            startWithFavorites: pane.cfg.startWithFavorites
            favoritesActive: pane.favoritesActive
            hideLabelsOnFavorites: pane.cfg.hideLabelsOnFavorites

            // Folders drill in place; Esc climbs back out (the window Shortcut
            // yields via folderOpen, like the menu view).
            onOpenFolderRequested: function(folderId) {
                if (pane.favoritesGroupedModel)
                    pane.favoritesGroupedModel.enterFolder(folderId)
            }
            onEscapePressed: nav.goBack()
            onFolderContextMenuRequested: folderId => pane.folderContextMenuRequested(folderId)
            onEmptyAreaContextMenuRequested: pane.emptyAreaContextMenuRequested()
        }

        ShuffleOverlay {
            id: shuffleOverlay
            anchors.fill: parent
            z: 10
            iconSize: pane.host.cellStyle.iconSize
        }
    }
}
