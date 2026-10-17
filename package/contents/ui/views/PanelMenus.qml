/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The panel's right-click menus: an app's (from any view), a search result's,
    a favourites folder's, the empty favourites area's and a menu folder's
    (#201). The panel says which to open; what a menu cannot do itself (bulk
    launch, the confirmations, closing) comes back as signals.
*/

import QtQuick

import "../widgets"

Item {
    id: menus

    // The launcher controller (AppGridController): its models and services.
    required property var plasmoidBridge
    // The panel's ConfigCache.
    required property var cfg
    // Pin / desktop / menu-editor actions (LauncherActions).
    required property var launcherActions
    property var appsModel: null
    property var searchModel: null
    // FavoritesManager: favourites and their folders.
    property var favoritesManager: null
    readonly property var _favoritesGroupedModel: favoritesManager ? favoritesManager.favoritesGroupedModel : null
    property var appletInterface: null
    property bool favoritesActive: false
    // The grid whose multi-selection the app menu's selection items change,
    // or null where there is none (search results, recents).
    property var selectionView: null

    signal bulkLaunchRequested(var sids, bool fromFolder)
    signal bulkHideRequested(var sids)
    signal renameFolderRequested(string folderId)
    signal closeRequested()

    readonly property var _menuModel: plasmoidBridge ? plasmoidBridge.menuTreeModel : null

    function showForApp(storageId, desktopFile, selectedSids, canSelect = true) {
        appMenu.showForApp(storageId, desktopFile, selectedSids, canSelect)
    }
    // A row of the search results that a KRunner runner gave, by its row
    // in the unified search model.
    function showForRunnerResult(index) {
        const item = searchModel ? searchModel.get(index) : null
        if (!item)
            return
        // The runner takes its own row (sourceIndex), not the unified one.
        appMenu.showForRunner(item.sourceIndex, searchModel.runnerActions(index),
                              plasmoidBridge.runner.favoriteId(item.sourceIndex))
    }
    function showForFolder(folderId) { appMenu.showForFolder(folderId) }
    function showForEmptyArea() { appMenu.showForEmptyArea() }
    function showForMenuFolder(menuPath) { menuFolderMenu.showFor(menuPath) }
    function close() {
        appMenu.close()
        menuFolderMenu.close()
    }

    // A menu-tree folder (#201): open it, launch the apps directly in it (not
    // its subfolders'), or edit it in kmenuedit, as the category bar offers.
    FolderContextMenu {
        id: menuFolderMenu
        appIdsOf: id => menus._menuModel ? menus._menuModel.folderAppIds(id) : []
        onOpenRequested: folderId => { if (menus._menuModel) menus._menuModel.enterFolder(folderId) }
        onLaunchAllRequested: appIds => menus.bulkLaunchRequested(appIds, true)

        AppGridMenuItem {
            text: i18nd("dev.xarbit.appgrid", "Edit in Menu Editor…")
            icon.name: "kmenuedit"
            onClicked: menus.launcherActions.editMenuItem(menuFolderMenu.folderId)
        }
    }

    AppContextMenu {
        id: appMenu
        appsModel: menus.appsModel
        // The folders too, so "Add to Folder" works for a favourite right-clicked
        // anywhere (grid, search) — not only on the favourites tab.
        favoritesManager: menus.favoritesManager
        foldersEnabled: menus.cfg.favoriteFoldersEnabled
        enableActivities: menus.cfg.enableActivities
        favoritesActive: menus.favoritesActive
        appletInterface: menus.appletInterface
        onOpenFolderRequested: folderId => { if (menus._favoritesGroupedModel) menus._favoritesGroupedModel.enterFolder(folderId) }
        onRenameFolderRequested: folderId => menus.renameFolderRequested(folderId)
        onFolderLaunchRequested: sids => menus.bulkLaunchRequested(sids, true)

        launcherActions: menus.launcherActions
        launchService: menus.plasmoidBridge.launchService
        systemActions: menus.plasmoidBridge.systemActions
        runner: menus.plasmoidBridge.runner
        onCloseRequested: menus.closeRequested()

        onBulkLaunchRequested: sids => menus.bulkLaunchRequested(sids, false)
        onBulkHideRequested: function(sids) {
            if (sids && sids.length > 0)
                menus.bulkHideRequested(sids)
        }
        // The selection items act on the grid that owns the selection; where
        // there is none they do nothing.
        onToggleSelectionRequested: function(sid) {
            if (menus.selectionView && sid)
                menus.selectionView.selection.toggleSelectionBySid(sid)
        }
        onClearSelectionRequested: {
            if (menus.selectionView)
                menus.selectionView.selection.clear()
        }
    }
}
