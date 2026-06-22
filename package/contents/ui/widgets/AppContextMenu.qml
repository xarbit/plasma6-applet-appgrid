/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Right-click context menu. Splits into two PlasmaComponents.Menu
    instances so each only holds items relevant to its mode — gating
    items inside one shared Menu via `visible: false` left ghost layout
    rows because PlasmaComponents.MenuItem's internal padding/insets
    don't fully collapse with implicitHeight=0. Truly-conditional items
    (jumplist, bulk Add/Remove favorites, Remove from Folder) use
    Instantiator so non-applicable rows don't exist at all.
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import "../js/favoriteid.js" as FavoriteId

Item {
    id: contextMenu

    // Launch/Hide go up to GridPanel for Kirigami.PromptDialog gating.
    // Pin / Desktop / Copy run inline (immediately reversible).
    signal bulkLaunchRequested(var sids)
    signal bulkHideRequested(var sids)
    signal toggleSelectionRequested(string sid)
    signal clearSelectionRequested()

    property var appletInterface: null
    property var appsModel: null
    property var sharedFavoritesModel: null
    // Favourites folders (issue #18): the editable grouped model + whether the
    // favourites tab is active, gating the folder menu rows.
    property var favoritesGroupedModel: null
    // Single source of truth for favourite mutations (controllers/FavoritesManager).
    property var favoritesManager: null
    property bool favoritesActive: false
    property string popupFolderId: ""
    // Folders available at all (model present + editable). The favourites-tab
    // gate is applied per-action where it matters (bulk/empty/folder menus).
    readonly property bool _canFolder: favoritesGroupedModel && favoritesGroupedModel.editable
    property bool _folderSubAdded: false
    property bool _bulkFolderSubAdded: false
    property bool _activitiesSubAdded: false
    // Id-set of the activities currently built into the submenu, so its item list
    // is only rebuilt when the set changes (not on every open).
    property string _activitiesSig: ""
    signal openFolderRequested(string folderId)
    signal renameFolderRequested(string folderId)
    signal launchFolderRequested(string folderId)

    // Plasmoid-glue callbacks, injected from the boundary:
    //   appActions(sid) -> list        launchAppAction(sid, idx)
    //   canManageInDiscover(sid) -> bool   openInDiscover(sid)
    //   pinToTaskManager(df)           addToDesktop(df)
    //   editApplication(sid)           runRunnerAction(rowIdx, actionIdx)
    // Hidden-apps list persists via AppFilterModel.hiddenAppsChanged
    // (GridPanel listens), so menu items just mutate the model.
    required property var appActions
    required property var launchAppAction
    required property var canManageInDiscover
    required property var openInDiscover
    required property var pinToTaskManager
    required property var addToDesktop
    // Capability probes (bool-returning) — hide actions that would no-op: the
    // Task Manager pin needs the plasmoid's D-Bus helper (absent when the daemon
    // runs without a plasmoid), Add to Desktop needs a Folder View desktop.
    required property var canPinToTaskManager
    required property var canAddToDesktop
    required property var editApplication
    required property var runRunnerAction

    // Popup snapshot — populated by showForApp() before popping the
    // appropriate Menu. Lives here so both child Menus + their dynamic
    // delegates share one source of truth.
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false
    property bool popupIsHidden: false
    // Re-probed on each open: capabilities can change (plasmoid added/removed,
    // desktop switched to/from Folder View).
    property bool popupCanPin: true
    property bool popupCanAddToDesktop: true
    property var popupActions: []
    // Activity submenu state for the right-clicked favourite: the running
    // activities and the ones it's pinned to (see ActivityFavoritesMenu).
    property var popupActivities: []
    property var popupLinkedActivities: []
    property list<string> popupSelectedSids: []
    property bool popupIsSelected: false
    // Whether the originating view supports multi-select. Search-results
    // + recents don't; gates the "Add/Remove from Selection" item out of
    // the single menu so it stops looking like a silent no-op.
    property bool popupCanSelect: true
    readonly property bool isMultiSelect: popupIsSelected
                                          && popupSelectedSids.length >= 2
    property int popupNonFavCount: 0
    property int popupFavCount: 0
    // KRunner row context: the RunnerFilterModel proxy row (the
    // sourceIndex on a runner row from UnifiedSearchModel.get) whose
    // secondary actions the runnerMenu is showing, plus the list itself.
    property int popupRunnerSourceIndex: -1
    property var popupRunnerActions: []
    // KAStats favorite id for an app-backed runner result ("applications:<id>"),
    // empty if it can't be favorited (#64).
    property string popupRunnerFavoriteId: ""
    property bool popupRunnerIsFavorite: false
    readonly property bool _canFavoriteRunner: popupRunnerFavoriteId.length > 0 && sharedFavoritesModel

    // Favorites-mutation rows lock out while a drag-reorder is in flight
    // to avoid clobbering KAStats state mid-move.
    readonly property bool _favsLocked: appletInterface
                                        && appletInterface.isDragInFlight

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
    // rather than Component.onCompleted because PlasmaComponents.Menu
    // constructs contentItem lazily on first open; running earlier would
    // silently no-op. The assignment is idempotent across re-opens.
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
        const prefixed = FavoriteId.toPrefixed(storageId)
        popupIsFavorite = sharedFavoritesModel
                          ? sharedFavoritesModel.isFavorite(prefixed)
                          : false

        var favs = 0
        if (isMultiSelect && sharedFavoritesModel) {
            for (var i = 0; i < popupSelectedSids.length; ++i) {
                if (sharedFavoritesModel.isFavorite(
                        FavoriteId.toPrefixed(popupSelectedSids[i])))
                    ++favs
            }
        }
        popupFavCount = favs
        popupNonFavCount = popupSelectedSids.length - favs
        popupActions = isMultiSelect ? [] : (contextMenu.appActions(storageId) || [])
        popupCanPin = contextMenu.canPinToTaskManager()
        popupCanAddToDesktop = contextMenu.canAddToDesktop()

        // Attach the "Add to Folder" submenu only for a favourite on the
        // favourites tab; a submenu's `visible` is its open-state, so it can't be
        // bound — add/remove it instead.
        if (!isMultiSelect) {
            // Any app can be added to a folder; a non-favourite is favourited in
            // the process (see the submenu handlers).
            const wantFolderSub = _canFolder && popupStorageId.length > 0
            if (wantFolderSub && !_folderSubAdded) {
                singleMenu.addMenu(addToFolderSubmenu)
                _folderSubAdded = true
            } else if (!wantFolderSub && _folderSubAdded) {
                singleMenu.removeMenu(addToFolderSubmenu)
                _folderSubAdded = false
            }

            // "Show in Favorites" activity submenu — attached whenever more than
            // one activity exists (a stable condition, so it's added once and
            // stays, like the folder submenu). Picking an activity on a
            // non-favourite favourites it there.
            const acts = sharedFavoritesModel ? sharedFavoritesModel.activities() : []
            const wantActivitiesSub = acts.length > 1
            if (wantActivitiesSub) {
                // Rebuild the item list only when the activity set actually
                // changes; a fresh array every open would churn the Instantiator
                // and corrupt the menu.
                const sig = acts.map(a => a.id).join("\n")
                if (sig !== _activitiesSig) {
                    popupActivities = acts
                    _activitiesSig = sig
                }
                popupLinkedActivities = popupIsFavorite
                    ? sharedFavoritesModel.linkedActivitiesFor(prefixed) : []
                if (!_activitiesSubAdded) {
                    singleMenu.addMenu(activitiesSubmenu)
                    _activitiesSubAdded = true
                }
            } else if (_activitiesSubAdded) {
                singleMenu.removeMenu(activitiesSubmenu)
                _activitiesSubAdded = false
            }
        } else {
            // Bulk "Add to Folder" — any selection; non-favourites are favourited.
            const wantBulkSub = _canFolder && popupSelectedSids.length > 0
            if (wantBulkSub && !_bulkFolderSubAdded) {
                bulkMenu.addMenu(addSelectionToFolderSubmenu)
                _bulkFolderSubAdded = true
            } else if (!wantBulkSub && _bulkFolderSubAdded) {
                bulkMenu.removeMenu(addSelectionToFolderSubmenu)
                _bulkFolderSubAdded = false
            }
        }

        if (isMultiSelect)
            bulkMenu.popup()
        else
            singleMenu.popup()
    }

    function showForRunner(runnerSourceIndex, actions, favoriteId) {
        const favId = favoriteId || ""
        if ((!actions || actions.length === 0) && favId.length === 0)
            return
        popupRunnerSourceIndex = runnerSourceIndex
        popupRunnerActions = actions || []
        popupRunnerFavoriteId = favId
        popupRunnerIsFavorite = _canFavoriteRunner && sharedFavoritesModel.isFavorite(favId)
        runnerMenu.popup()
    }

    function showForFolder(folderId) {
        if (!_canFolder || !folderId)
            return
        popupFolderId = folderId
        folderMenu.popup()
    }

    function showForEmptyArea() {
        if (!_canFolder)
            return
        emptyAreaMenu.popup()
    }

    function close() {
        singleMenu.close()
        bulkMenu.close()
        runnerMenu.close()
        folderMenu.close()
        emptyAreaMenu.close()
    }

    function _desktopFileFor(sid) {
        if (!appsModel || !sid) return ""
        const a = appsModel.getByStorageId(sid)
        return (a && a.desktopFile) ? a.desktopFile : ""
    }

    function _bulkAdd(addFn) {
        if (!appsModel) return
        const sids = popupSelectedSids
        for (var i = 0; i < sids.length; ++i) {
            const df = _desktopFileFor(sids[i])
            if (df) addFn(df)
        }
    }

    // Toggle a single already-prefixed KAStats favorite id on/off. Shared by the
    // grid-app row and the app-backed runner-result row.
    function _toggleFavorite(id) {
        if (favoritesManager && id)
            favoritesManager.toggleFavorite(FavoriteId.stripPrefix(id))
    }

    function _removeFromAnyFolder(sid) {
        if (favoritesManager)
            favoritesManager.removeFromAnyFolder(sid)
    }

    function _ensureFavorite(sid) {
        if (favoritesManager)
            favoritesManager.ensureFavorite(sid)
    }

    // Add the whole selection to @p folderId, favouriting any that aren't (#18).
    function _addSelectionToFolder(folderId) {
        if (!favoritesGroupedModel || !folderId)
            return
        for (var i = 0; i < popupSelectedSids.length; ++i) {
            _ensureFavorite(popupSelectedSids[i])
            favoritesGroupedModel.addToFolder(folderId, popupSelectedSids[i])
        }
    }

    function _bulkSetFavorite(addNotRemove) {
        if (!favoritesManager) return
        const sids = popupSelectedSids
        for (var i = 0; i < sids.length; ++i) {
            if (addNotRemove) {
                favoritesManager.ensureFavorite(sids[i])
            } else {
                favoritesManager.removeFavorite(sids[i])
            }
        }
    }

    function _copySelectedPaths() {
        const sids = popupSelectedSids
        var paths = []
        for (var i = 0; i < sids.length; ++i) {
            const df = _desktopFileFor(sids[i])
            if (df) paths.push(df)
        }
        bulkPathClipboard.text = paths.join("\n")
        bulkPathClipboard.selectAll()
        bulkPathClipboard.copy()
    }

    // Hidden TextEdit clipboard sink — same pattern as PrefixInfoView,
    // sidesteps QtQuick.Dialogs / Clipboard plugin imports.
    TextEdit { id: bulkPathClipboard; visible: false }

    AppGridMenu {
        id: singleMenu

        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(singleMenu)

        Instantiator {
            model: contextMenu.popupActions
            delegate: PlasmaComponents.MenuItem {
                required property var modelData
                required property int index
                icon.name: modelData.icon || ""
                text: modelData.text
                onClicked: {
                    contextMenu.launchAppAction(contextMenu.popupStorageId, index)
                    singleMenu.close()
                }
            }
            onObjectAdded: (idx, obj) => singleMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }

        PlasmaComponents.MenuItem {
            icon.name: contextMenu.popupIsFavorite ? "bookmark-remove" : "bookmark-new"
            text: contextMenu.popupIsFavorite
                  ? i18nd("dev.xarbit.appgrid", "Remove from Favorites")
                  : i18nd("dev.xarbit.appgrid", "Add to Favorites")
            enabled: !contextMenu._favsLocked
            onClicked: {
                if (contextMenu.popupStorageId)
                    contextMenu._toggleFavorite(FavoriteId.toPrefixed(contextMenu.popupStorageId))
            }
        }

        // Take the app out of its folder (it stays a favourite) — only shown
        // when it is currently in one. Instantiator + active rather than
        // visible:false, which leaves a blank ghost row (see header) (#18).
        Instantiator {
            active: contextMenu._canFolder && contextMenu.favoritesGroupedModel
                    && contextMenu.favoritesGroupedModel.folderOfMember(contextMenu.popupStorageId).length > 0
            delegate: PlasmaComponents.MenuItem {
                icon.name: "folder-remove"
                text: i18nd("dev.xarbit.appgrid", "Remove from Folder")
                onClicked: contextMenu._removeFromAnyFolder(contextMenu.popupStorageId)
            }
            onObjectAdded: (idx, obj) => singleMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }


        // Instantiator + active rather than `visible: false` so the row
        // doesn't leave a blank padding gap when the originating view
        // (search-results, prefix view) has no multi-select.
        Instantiator {
            active: contextMenu.popupCanSelect
            delegate: PlasmaComponents.MenuItem {
                icon.name: contextMenu.popupIsSelected ? "edit-select-none" : "edit-select-all"
                text: contextMenu.popupIsSelected
                      ? i18nd("dev.xarbit.appgrid", "Remove from Selection")
                      : i18nd("dev.xarbit.appgrid", "Add to Selection")
                onClicked: contextMenu.toggleSelectionRequested(contextMenu.popupStorageId)
            }
            onObjectAdded: (idx, obj) => singleMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }

        Instantiator {
            active: contextMenu.popupCanSelect
            delegate: PlasmaComponents.MenuSeparator {}
            onObjectAdded: (idx, obj) => singleMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }

        PlasmaComponents.MenuItem {
            icon.name: "pin"
            text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
            visible: contextMenu.popupCanPin
            onClicked: contextMenu.pinToTaskManager(contextMenu.popupDesktopFile)
        }

        PlasmaComponents.MenuItem {
            icon.name: "desktop"
            text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
            visible: contextMenu.popupCanAddToDesktop
            onClicked: contextMenu.addToDesktop(contextMenu.popupDesktopFile)
        }

        PlasmaComponents.MenuItem {
            icon.name: "document-edit"
            text: i18nd("dev.xarbit.appgrid", "Edit Application")
            onClicked: contextMenu.editApplication(contextMenu.popupStorageId)
        }

        // Truly-conditional item — Instantiator creates/destroys instead
        // of visible:false, which leaves a blank row in PlasmaComponents.Menu.
        Instantiator {
            active: contextMenu.canManageInDiscover(contextMenu.popupStorageId)
            delegate: PlasmaComponents.MenuItem {
                icon.name: "plasmadiscover"
                text: i18nd("dev.xarbit.appgrid", "Manage in Discover…")
                onClicked: contextMenu.openInDiscover(contextMenu.popupStorageId)
            }
            onObjectAdded: (idx, obj) => singleMenu.addItem(obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }

        PlasmaComponents.MenuSeparator {}

        PlasmaComponents.MenuItem {
            icon.name: contextMenu.popupIsHidden ? "view-visible" : "view-hidden"
            text: contextMenu.popupIsHidden
                  ? i18nd("dev.xarbit.appgrid", "Unhide Application")
                  : i18nd("dev.xarbit.appgrid", "Hide Application")
            onClicked: {
                if (!contextMenu.appsModel || !contextMenu.popupStorageId) return
                if (contextMenu.popupIsHidden)
                    contextMenu.appsModel.unhideApp(contextMenu.popupStorageId)
                else
                    contextMenu.appsModel.hideByStorageId(contextMenu.popupStorageId)
            }
        }
    }

    AppGridMenu {
        id: bulkMenu

        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(bulkMenu)

        // Add N inserts at 0 (top). Remove N lands at 0 or 1 based on
        // whether Add N is already present — both at top, Add N above.
        Instantiator {
            active: contextMenu.popupNonFavCount > 0
            delegate: PlasmaComponents.MenuItem {
                icon.name: "bookmark-new"
                text: i18ndp("dev.xarbit.appgrid",
                             "Add %1 to Favorites", "Add %1 to Favorites",
                             contextMenu.popupNonFavCount)
                enabled: !contextMenu._favsLocked
                onClicked: contextMenu._bulkSetFavorite(true)
            }
            onObjectAdded: (idx, obj) => bulkMenu.insertItem(0, obj)
            onObjectRemoved: (idx, obj) => bulkMenu.removeItem(obj)
        }

        Instantiator {
            active: contextMenu.popupFavCount > 0
            delegate: PlasmaComponents.MenuItem {
                icon.name: "bookmark-remove"
                text: i18ndp("dev.xarbit.appgrid",
                             "Remove %1 from Favorites", "Remove %1 from Favorites",
                             contextMenu.popupFavCount)
                enabled: !contextMenu._favsLocked
                onClicked: contextMenu._bulkSetFavorite(false)
            }
            onObjectAdded: (idx, obj) => bulkMenu.insertItem(
                contextMenu.popupNonFavCount > 0 ? 1 : 0, obj)
            onObjectRemoved: (idx, obj) => bulkMenu.removeItem(obj)
        }


        PlasmaComponents.MenuItem {
            icon.name: "pin"
            text: i18ndp("dev.xarbit.appgrid",
                         "Pin %1 to Task Manager", "Pin %1 to Task Manager",
                         contextMenu.popupSelectedSids.length)
            visible: contextMenu.popupCanPin
            onClicked: contextMenu._bulkAdd(contextMenu.pinToTaskManager)
        }

        PlasmaComponents.MenuItem {
            icon.name: "desktop"
            text: i18ndp("dev.xarbit.appgrid",
                         "Add %1 to Desktop", "Add %1 to Desktop",
                         contextMenu.popupSelectedSids.length)
            visible: contextMenu.popupCanAddToDesktop
            onClicked: contextMenu._bulkAdd(contextMenu.addToDesktop)
        }

        PlasmaComponents.MenuItem {
            icon.name: "system-run"
            text: i18ndp("dev.xarbit.appgrid",
                         "Launch %1 application", "Launch %1 applications",
                         contextMenu.popupSelectedSids.length)
            onClicked: contextMenu.bulkLaunchRequested(contextMenu.popupSelectedSids)
        }

        PlasmaComponents.MenuSeparator {}

        PlasmaComponents.MenuItem {
            icon.name: "edit-copy"
            text: i18ndp("dev.xarbit.appgrid",
                         "Copy %1 path", "Copy %1 paths",
                         contextMenu.popupSelectedSids.length)
            onClicked: contextMenu._copySelectedPaths()
        }

        PlasmaComponents.MenuItem {
            icon.name: "view-hidden"
            text: i18ndp("dev.xarbit.appgrid",
                         "Hide %1 application", "Hide %1 applications",
                         contextMenu.popupSelectedSids.length)
            onClicked: contextMenu.bulkHideRequested(contextMenu.popupSelectedSids)
        }

        PlasmaComponents.MenuSeparator {}

        PlasmaComponents.MenuItem {
            icon.name: "edit-select-none"
            text: i18nd("dev.xarbit.appgrid", "Remove from Selection")
            onClicked: contextMenu.toggleSelectionRequested(contextMenu.popupStorageId)
        }
    }

    // Folder cell actions (issue #18). Right-clicking a folder in the favourites
    // grid; "Ungroup" returns its members to loose favourites.
    AppGridMenu {
        id: folderMenu

        PlasmaComponents.MenuItem {
            icon.name: "folder-open"
            text: i18nd("dev.xarbit.appgrid", "Open Folder")
            onClicked: {
                contextMenu.openFolderRequested(contextMenu.popupFolderId)
                folderMenu.close()
            }
        }
        // Launch every app in the folder, through the same bulk-launch path (so
        // the "open many at once?" confirm threshold still applies).
        PlasmaComponents.MenuItem {
            icon.name: "system-run"
            text: i18nd("dev.xarbit.appgrid", "Launch All")
            enabled: contextMenu.favoritesGroupedModel
                     && contextMenu.favoritesGroupedModel.folderMembers(contextMenu.popupFolderId).length > 0
            onClicked: {
                contextMenu.launchFolderRequested(contextMenu.popupFolderId)
                folderMenu.close()
            }
        }
        PlasmaComponents.MenuItem {
            icon.name: "edit-rename"
            text: i18nd("dev.xarbit.appgrid", "Rename Folder…")
            onClicked: {
                contextMenu.renameFolderRequested(contextMenu.popupFolderId)
                folderMenu.close()
            }
        }
        PlasmaComponents.MenuSeparator {}
        PlasmaComponents.MenuItem {
            icon.name: "folder-remove"
            text: i18nd("dev.xarbit.appgrid", "Ungroup Folder")
            enabled: contextMenu.favoritesGroupedModel
            onClicked: {
                contextMenu.favoritesGroupedModel.ungroupFolder(contextMenu.popupFolderId)
                folderMenu.close()
            }
        }
    }

    // "Show in Favorites" submenu — attached to the single menu only for a
    // favourite with more than one activity (see showForApp). Pins the favourite
    // to the chosen activities (state lives in KActivities, shared by every variant).
    ActivityFavoritesMenu {
        id: activitiesSubmenu
        activities: contextMenu.popupActivities
        linkedActivities: contextMenu.popupLinkedActivities
        isFavorite: contextMenu.popupIsFavorite
        onChosen: activityIds => {
            if (contextMenu.sharedFavoritesModel) {
                contextMenu.sharedFavoritesModel.setLinkedActivities(
                    FavoriteId.toPrefixed(contextMenu.popupStorageId), activityIds)
            }
            contextMenu.close()
        }
    }

    // "Add to Folder" submenu — attached to the single menu only for favourites
    // (see showForApp). Adds (and favourites, if needed) the clicked app (#18).
    FolderTargetMenu {
        id: addToFolderSubmenu
        foldersModel: contextMenu.favoritesGroupedModel
        disabledMemberSid: contextMenu.popupStorageId
        onFolderChosen: folderId => {
            contextMenu._ensureFavorite(contextMenu.popupStorageId)
            contextMenu.favoritesGroupedModel.addToFolder(folderId, contextMenu.popupStorageId)
            contextMenu.close()
        }
        onNewFolderRequested: {
            contextMenu._ensureFavorite(contextMenu.popupStorageId)
            contextMenu.favoritesGroupedModel.createFolderFromMembers([contextMenu.popupStorageId])
            contextMenu.close()
        }
    }

    // Bulk "Add to Folder" — attached to the multi-select menu; adds the whole
    // selection to a folder, or makes a new folder from it (#18).
    FolderTargetMenu {
        id: addSelectionToFolderSubmenu
        foldersModel: contextMenu.favoritesGroupedModel
        onFolderChosen: folderId => {
            contextMenu._addSelectionToFolder(folderId)
            contextMenu.clearSelectionRequested()
            contextMenu.close()
        }
        onNewFolderRequested: {
            for (var i = 0; i < contextMenu.popupSelectedSids.length; ++i)
                contextMenu._ensureFavorite(contextMenu.popupSelectedSids[i])
            contextMenu.favoritesGroupedModel.createFolderFromMembers(
                contextMenu.popupSelectedSids, i18nd("dev.xarbit.appgrid", "New Folder"))
            contextMenu.clearSelectionRequested()
            contextMenu.close()
        }
    }

    // Right-click on empty favourites space: create a new (empty) folder (#18).
    AppGridMenu {
        id: emptyAreaMenu
        PlasmaComponents.MenuItem {
            icon.name: "folder-new"
            text: i18nd("dev.xarbit.appgrid", "Create Folder…")
            enabled: contextMenu.favoritesGroupedModel
            onClicked: contextMenu.favoritesGroupedModel.createEmptyFolder()
        }
    }

    // KRunner secondary actions (e.g. calculator "Copy result"). Same menu
    // owner as the app context menus so bounds/padding/close-tracking fixes
    // apply once.
    AppGridMenu {
        id: runnerMenu

        onAboutToHide: contextMenu._trackClose()
        onAboutToShow: contextMenu._stopMenuBounce(runnerMenu)

        // Favorite an app-backed search result (apps, System Settings modules)
        // straight from the search list, the same as a grid app (#64). The id is
        // already the prefixed "applications:<id>" KAStats form.
        PlasmaComponents.MenuItem {
            visible: contextMenu._canFavoriteRunner
            icon.name: contextMenu.popupRunnerIsFavorite ? "bookmark-remove" : "bookmark-new"
            text: contextMenu.popupRunnerIsFavorite
                  ? i18nd("dev.xarbit.appgrid", "Remove from Favorites")
                  : i18nd("dev.xarbit.appgrid", "Add to Favorites")
            onClicked: {
                contextMenu._toggleFavorite(contextMenu.popupRunnerFavoriteId)
                runnerMenu.close()
            }
        }
        PlasmaComponents.MenuSeparator {
            visible: contextMenu._canFavoriteRunner && contextMenu.popupRunnerActions.length > 0
        }

        Instantiator {
            model: contextMenu.popupRunnerActions
            delegate: PlasmaComponents.MenuItem {
                required property var modelData
                required property int index
                icon.name: modelData.icon || ""
                text: modelData.text || ""
                onClicked: {
                    contextMenu.runRunnerAction(contextMenu.popupRunnerSourceIndex, index)
                    runnerMenu.close()
                }
            }
            onObjectAdded: (idx, obj) => runnerMenu.insertItem(idx, obj)
            onObjectRemoved: (idx, obj) => runnerMenu.removeItem(obj)
        }
    }
}
