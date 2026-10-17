/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The right-click menus of the launcher's apps and folders: one app
    (SingleAppMenu), a multi-selection (SelectionMenu), a favourites folder
    (FavoritesFolderMenu), the empty favourites area and a KRunner result
    (RunnerContextMenu). Each is its own PlasmaComponents.Menu holding only
    its own rows. This owner reads what the menu is opened for once, as it
    opens, and holds what they all use: the models and services, and the
    signals for what the menus leave to the panel.
*/

pragma ComponentBehavior: Bound

import QtQuick
import "../js/favoriteid.js" as FavoriteId

Item {
    id: contextMenu

    // Launch / Hide go up to the panel for their confirmation; the rest run
    // inline (they are easy to undo).
    signal bulkLaunchRequested(var sids)
    signal bulkHideRequested(var sids)
    signal toggleSelectionRequested(string sid)
    signal clearSelectionRequested()
    signal openFolderRequested(string folderId)
    signal renameFolderRequested(string folderId)
    // A folder's "Launch All": its apps, for the bulk launch path.
    signal folderLaunchRequested(var sids)

    property var appletInterface: null
    property var appsModel: null
    // Single source of truth for favourites (controllers/FavoritesManager):
    // the mutations, and the models read below.
    property var favoritesManager: null
    readonly property var sharedFavoritesModel: favoritesManager ? favoritesManager.sharedFavoritesModel : null
    // Favourites folders (issue #18): the editable grouped model, gating the
    // folder menu rows.
    readonly property var favoritesGroupedModel: favoritesManager ? favoritesManager.favoritesGroupedModel : null
    // Per-activity favourites/folders opt-in; off keeps everything global and
    // hides the activity menus.
    property bool enableActivities: false
    // "Group favorites into folders" setting; off hides every folder action
    // (Add to Folder, New Folder, Remove from Folder).
    property bool foldersEnabled: false
    property bool favoritesActive: false

    // The services the rows call:
    //   launcherActions  pin to the task manager, add to the desktop, edit
    //                    (LauncherActions), with the canPin/canAdd probes
    //   launchService    an app's jump-list actions (LaunchService)
    //   systemActions    Discover (SystemActions)
    //   runner           a KRunner result's actions (RunnerService)
    required property var launcherActions
    required property var launchService
    required property var systemActions
    required property var runner

    // Folders available at all (feature enabled + model present + editable).
    readonly property bool _canFolder: foldersEnabled && !!favoritesGroupedModel && favoritesGroupedModel.editable
    // Folders are single level: creating / adding to a folder is only allowed at
    // the top level, never while drilled inside one (no nesting). "Remove from
    // Folder" stays available inside — it uses _canFolder. (#18)
    readonly property bool _canCreateFolder: _canFolder && !favoritesGroupedModel.canGoBack

    // What the menu was opened for — read by showForApp() as it opens, so
    // nothing goes stale while it shows.
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false
    property bool popupIsHidden: false
    // Re-probed on each open: capabilities can change (plasmoid added/removed,
    // desktop switched to/from Folder View).
    property bool popupCanPin: true
    property bool popupCanAddToDesktop: true
    property bool popupCanManageInDiscover: false
    property var popupActions: []
    property list<string> popupSelectedSids: []
    property bool popupIsSelected: false
    // Whether the originating view has a multi-selection (the search results
    // don't); gates "Add/Remove from Selection".
    property bool popupCanSelect: true
    readonly property bool isMultiSelect: popupIsSelected && popupSelectedSids.length >= 2
    property int popupNonFavCount: 0
    property int popupFavCount: 0
    // Whether the app is in a favourites folder ("Remove from Folder").
    property bool popupInFolder: false

    // Favourite rows lock out while a drag-reorder is in flight, so they
    // don't clobber the KActivities state mid-move.
    readonly property bool _favsLocked: !!appletInterface && appletInterface.isDragInFlight

    // Same-row reclick guard. Menu's onAboutToHide fires synchronously on
    // click-outside dismissal, then the same click continues to the source
    // and re-emits contextMenuRequested. Storing the just-closed storageId
    // turns that into a clean toggle inside the 250 ms window.
    property string _lastClosedStorageId: ""
    Timer {
        id: reopenGuard
        interval: 250
        onTriggered: contextMenu._lastClosedStorageId = ""
    }
    function _trackClose() {
        _lastClosedStorageId = popupStorageId
        reopenGuard.restart()
    }

    // Kill the rubber-band overshoot when a menu overflows the popup and
    // scrolls (long jumplists like Steam) — #154. Called on aboutToShow
    // because PlasmaComponents.Menu builds contentItem lazily on first open.
    function _stopMenuBounce(menu) {
        if (menu.contentItem && "boundsBehavior" in menu.contentItem)
            menu.contentItem.boundsBehavior = Flickable.StopAtBounds
    }

    function showForApp(storageId, desktopFile, selectedSids, canSelect = true) {
        if (storageId && _lastClosedStorageId === storageId) {
            _lastClosedStorageId = ""
            reopenGuard.stop()
            return
        }
        popupStorageId = storageId
        popupDesktopFile = desktopFile
        popupSelectedSids = selectedSids || []
        popupIsSelected = popupSelectedSids.indexOf(storageId) >= 0
        popupCanSelect = canSelect
        popupIsHidden = appsModel ? appsModel.isHidden(storageId) : false
        popupInFolder = !!storageId && _canFolder
                        && favoritesGroupedModel.folderOfMember(storageId).length > 0
        popupIsFavorite = !!favoritesManager && favoritesManager.isFavorite(storageId)

        let favs = 0
        if (isMultiSelect && favoritesManager)
            favs = popupSelectedSids.filter(sid => favoritesManager.isFavorite(sid)).length
        popupFavCount = favs
        popupNonFavCount = popupSelectedSids.length - favs
        popupActions = isMultiSelect ? [] : (launchService.appActions(storageId) || [])
        popupCanPin = launcherActions.canPinToTaskManager()
        popupCanAddToDesktop = launcherActions.canAddToDesktop()
        popupCanManageInDiscover = !isMultiSelect && systemActions.canManageInDiscover(storageId)

        if (isMultiSelect)
            selectionMenu.showForSelection()
        else
            appMenu.showForApp()
    }

    function showForRunner(runnerSourceIndex, actions, favoriteId) {
        const favId = favoriteId || ""
        if ((!actions || actions.length === 0) && favId.length === 0)
            return
        const canFavorite = favId.length > 0 && !!sharedFavoritesModel
        runnerMenu.showFor(runnerSourceIndex, actions, canFavorite ? favId : "",
                           canFavorite && sharedFavoritesModel.isFavorite(favId))
    }

    function showForFolder(folderId) {
        if (_canFolder && folderId)
            folderMenu.showForFolder(folderId)
    }

    function showForEmptyArea() {
        if (_canCreateFolder)
            emptyAreaMenu.popup()
    }

    function close() {
        appMenu.close()
        selectionMenu.close()
        runnerMenu.close()
        folderMenu.close()
        emptyAreaMenu.close()
    }

    // Toggle an already-prefixed KActivities favourite id. Shared by the app
    // menu and the app-backed runner result.
    function _toggleFavorite(id) {
        if (favoritesManager && id)
            favoritesManager.toggleFavorite(FavoriteId.stripPrefix(id))
    }

    function _copyText(text) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
    }

    // Hidden TextEdit as the clipboard sink — same pattern as PrefixInfoView,
    // sidesteps the QtQuick.Dialogs / Clipboard plugin imports.
    TextEdit { id: clipboard; visible: false }

    SingleAppMenu {
        id: appMenu
        owner: contextMenu
        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(appMenu)
    }

    SelectionMenu {
        id: selectionMenu
        owner: contextMenu
        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(selectionMenu)
    }

    FavoritesFolderMenu {
        id: folderMenu
        owner: contextMenu
    }

    // Right-click on empty favourites space: create a new (empty) folder (#18).
    AppGridMenu {
        id: emptyAreaMenu
        AppGridMenuItem {
            icon.name: "folder-new"
            text: i18nd("dev.xarbit.appgrid", "Create Folder…")
            enabled: !!contextMenu.favoritesGroupedModel
            onClicked: contextMenu.favoritesGroupedModel.createEmptyFolder()
        }
    }

    // KRunner search results. Same owner as the app menus so the bounds,
    // padding and close tracking apply once.
    RunnerContextMenu {
        id: runnerMenu
        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(runnerMenu)
        onFavoriteToggled: favoriteId => contextMenu._toggleFavorite(favoriteId)
        onActionTriggered: function(sourceIndex, actionIndex) {
            if (contextMenu.runner.runAction(sourceIndex, actionIndex))
                contextMenu.closeRequested()
        }
    }

    // A runner action ran: the launcher closes.
    signal closeRequested()
}
