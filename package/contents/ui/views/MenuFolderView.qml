/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Read-only drill-down over the kmenuedit menu tree, for the By Category view
    when "group categories into folders" is on (issue #201).

    This is a thin host: the grid itself is an AppGridView bound to the menu tree
    (a grouped model), so the icon delegate, selection, drag-and-drop and the app
    context menu are exactly the regular grid's — no duplication. The menu tree is
    read-only (groupEditable: false), so reorder / drag-to-folder / create-folder
    are off. This view only adds the drill chrome (back + breadcrumb) and routes
    folder activation to enterFolder / goBack instead of the favourites overlay.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../widgets"

Item {
    id: root

    // MenuTreeModel: AbstractGroupedModel rows for the current path, plus
    // enterFolder / goBack / canGoBack / currentFolderName.
    property var menuModel: null
    property var appsModel: null
    property var sharedFavoritesModel: null
    property var favoritesManager: null
    property int favoriteIdRole: -1
    property var dragSource: null
    property var searchField: null

    property int columns: 5
    property real cellWidth: 100
    property real cellHeight: 100
    property real iconSize: Kirigami.Units.iconSizes.large
    property real fontScale: 1.0
    property bool reduceGridSpacing: false
    property bool shadowEnabled: false
    property int hoverAnimation: 0
    property bool hoverHighlight: true
    property bool showScrollbars: true
    // Drop folders with no app anywhere in their subtree ("hide empty categories").
    property bool hideEmpty: false

    signal launched(string sid)
    signal categoryNavRequested(int direction)
    // Right-click on a folder → edit it in the menu editor (menuPath = kmenuedit
    // relPath, trailing slash stripped).
    signal folderContextRequested(string menuPath)
    // Right-click on an app → the shared app context menu (host owns it).
    signal appContextRequested(string sid, string desktopFile, var selectedSids)
    signal bulkLaunchRequested(var sids)

    // Drill selection + the canGoBack mirror, shared with the favourites grid.
    readonly property alias canGoBack: nav.canGoBack
    function focusGrid() { nav.focusGrid() }
    function resetToRoot() { if (menuModel) menuModel.resetToRoot() }
    // Full reset for close: clears the grid scroll/selection + nav memory (the
    // model floor is reset separately via setRootPath).
    function reset() { nav.reset() }

    DrillNavigator {
        id: nav
        model: root.menuModel
        grid: menuGrid
    }

    // Push hideEmpty into the (controller-owned) model; it rebuilds its rows.
    Binding {
        target: root.menuModel
        property: "hideEmpty"
        value: root.hideEmpty
        when: !!root.menuModel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // Back + breadcrumb (read-only: the menu tree isn't editable).
        DrillBar {
            Layout.fillWidth: true
            model: root.menuModel
            editable: false
        }

        AppGridView {
            id: menuGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: root.showScrollbars }

            model: root.menuModel
            groupedModel: root.menuModel
            groupEditable: false        // read-only: kmenuedit owns authoring
            favoritesActive: false
            showRecentApps: false
            hideLabelsOnFavorites: false

            appsModel: root.appsModel
            sharedFavoritesModel: root.sharedFavoritesModel
            favoritesManager: root.favoritesManager
            favoriteIdRole: root.favoriteIdRole
            dragSource: root.dragSource
            searchField: root.searchField

            columns: root.columns
            adaptiveColumns: true
            iconSize: root.iconSize
            fontScale: root.fontScale
            reduceGridSpacing: root.reduceGridSpacing
            hoverAnimation: root.hoverAnimation
            shadowEnabled: root.shadowEnabled
            hoverHighlight: root.hoverHighlight
            animateHighlight: root.hoverAnimation > 0
            sortFavoritesAlphabetically: false

            // Esc with no selection to clear → climb out one folder level. At the
            // root canGoBack is false, so the (re-enabled) window Shortcut closes.
            onEscapePressed: nav.goBack()
            // Folder activation drills in place (not the favourites overlay).
            onOpenFolderRequested: folderId => {
                if (root.menuModel)
                    root.menuModel.enterFolder(folderId)
            }
            onFolderContextMenuRequested: folderId => root.folderContextRequested(folderId.replace(/\/$/, ""))
            // App rows launch via launchFavorite → recentLaunched (sid in hand).
            onRecentLaunched: sid => root.launched(sid)
            onCategoryNavRequested: direction => root.categoryNavRequested(direction)
            onBulkLaunchRequested: sids => root.bulkLaunchRequested(sids)
            onContextMenuRequested: (index, sid, desktopFile) =>
                root.appContextRequested(sid, desktopFile, menuGrid.selectedSidList())
        }
    }
}
