/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Right-click context menu. Splits into two PlasmaComponents.Menu
    instances so each only holds items relevant to its mode — gating
    items inside one shared Menu via `visible: false` left ghost layout
    rows because PlasmaComponents.MenuItem's internal padding/insets
    don't fully collapse with implicitHeight=0. Truly-conditional items
    (jumplist, bulk Add/Remove favorites) use Instantiator so
    non-applicable rows don't exist at all.
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import "../js/favoriteid.js" as FavoriteId

Item {
    id: contextMenu

    Kicker.ProcessRunner { id: processRunner }
    Kicker.ContainmentInterface { id: containmentInterface }

    // Launch/Hide go up to GridPanel for Kirigami.PromptDialog gating.
    // Pin / Desktop / Copy run inline (immediately reversible).
    signal bulkLaunchRequested(var sids)
    signal bulkHideRequested(var sids)
    signal toggleSelectionRequested(string sid)

    property var appletInterface: null
    property var appsModel: null
    property var sharedFavoritesModel: null

    // Popup snapshot — populated by showForApp() before popping the
    // appropriate Menu. Lives here so both child Menus + their dynamic
    // delegates share one source of truth.
    property int popupIndex: -1
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false
    property var popupActions: []
    property list<string> popupSelectedSids: []
    property bool popupIsSelected: false
    readonly property bool isMultiSelect: popupIsSelected
                                          && popupSelectedSids.length >= 2
    property int popupNonFavCount: 0
    property int popupFavCount: 0

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

    function showForApp(index, storageId, desktopFile, selectedSids) {
        if (storageId && _lastClosedStorageId === storageId) {
            _lastClosedStorageId = ""
            reopenGuard.stop()
            return
        }
        popupIndex = index
        popupStorageId = storageId
        popupDesktopFile = desktopFile
        popupSelectedSids = selectedSids || []
        popupIsSelected = popupSelectedSids.indexOf(storageId) >= 0
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
        popupActions = isMultiSelect ? [] : (Plasmoid.appActions(storageId) || [])

        if (isMultiSelect)
            bulkMenu.popup()
        else
            singleMenu.popup()
    }

    function close() {
        singleMenu.close()
        bulkMenu.close()
    }

    function _desktopFileFor(sid) {
        if (!appsModel || !sid) return ""
        const a = appsModel.getByStorageId(sid)
        return (a && a.desktopFile) ? a.desktopFile : ""
    }

    function _bulkAddLauncher(target) {
        if (!appsModel || !appletInterface) return
        const sids = popupSelectedSids
        for (var i = 0; i < sids.length; ++i) {
            const df = _desktopFileFor(sids[i])
            if (df) containmentInterface.addLauncher(appletInterface, target, df)
        }
    }

    function _bulkSetFavorite(addNotRemove) {
        if (!sharedFavoritesModel) return
        const sids = popupSelectedSids
        for (var i = 0; i < sids.length; ++i) {
            const prefixed = FavoriteId.toPrefixed(sids[i])
            const isFav = sharedFavoritesModel.isFavorite(prefixed)
            if (addNotRemove && !isFav)
                sharedFavoritesModel.addFavorite(prefixed)
            else if (!addNotRemove && isFav)
                sharedFavoritesModel.removeFavorite(prefixed)
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

    PlasmaComponents.Menu {
        id: singleMenu

        onAboutToHide: contextMenu._trackClose()

        Instantiator {
            model: contextMenu.popupActions
            delegate: PlasmaComponents.MenuItem {
                required property var modelData
                required property int index
                icon.name: modelData.icon || ""
                text: modelData.text
                onClicked: {
                    Plasmoid.launchAppAction(contextMenu.popupStorageId, index)
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
                if (!contextMenu.sharedFavoritesModel) return
                const sid = contextMenu.popupStorageId
                if (!sid) return
                const prefixed = FavoriteId.toPrefixed(sid)
                if (contextMenu.sharedFavoritesModel.isFavorite(prefixed))
                    contextMenu.sharedFavoritesModel.removeFavorite(prefixed)
                else
                    contextMenu.sharedFavoritesModel.addFavorite(prefixed)
            }
        }

        PlasmaComponents.MenuItem {
            icon.name: contextMenu.popupIsSelected ? "edit-select-none" : "edit-select-all"
            text: contextMenu.popupIsSelected
                  ? i18nd("dev.xarbit.appgrid", "Remove from Selection")
                  : i18nd("dev.xarbit.appgrid", "Add to Selection")
            onClicked: contextMenu.toggleSelectionRequested(contextMenu.popupStorageId)
        }

        PlasmaComponents.MenuSeparator {}

        PlasmaComponents.MenuItem {
            icon.name: "pin"
            text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
            onClicked: containmentInterface.addLauncher(
                contextMenu.appletInterface,
                Kicker.ContainmentInterface.TaskManager,
                contextMenu.popupDesktopFile)
        }

        PlasmaComponents.MenuItem {
            icon.name: "desktop"
            text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
            onClicked: containmentInterface.addLauncher(
                contextMenu.appletInterface,
                Kicker.ContainmentInterface.Desktop,
                contextMenu.popupDesktopFile)
        }

        PlasmaComponents.MenuItem {
            icon.name: "document-edit"
            text: i18nd("dev.xarbit.appgrid", "Edit Application")
            onClicked: processRunner.runMenuEditor(contextMenu.popupStorageId)
        }

        // Truly-conditional item — Instantiator creates/destroys instead
        // of visible:false, which leaves a blank row in PlasmaComponents.Menu.
        Instantiator {
            active: Plasmoid.canManageInDiscover(contextMenu.popupStorageId)
            delegate: PlasmaComponents.MenuItem {
                icon.name: "plasmadiscover"
                text: i18nd("dev.xarbit.appgrid", "Manage in Discover…")
                onClicked: Plasmoid.openInDiscover(contextMenu.popupStorageId)
            }
            onObjectAdded: (idx, obj) => singleMenu.addItem(obj)
            onObjectRemoved: (idx, obj) => singleMenu.removeItem(obj)
        }

        PlasmaComponents.MenuSeparator {}

        PlasmaComponents.MenuItem {
            icon.name: "view-hidden"
            text: i18nd("dev.xarbit.appgrid", "Hide Application")
            onClicked: {
                if (!contextMenu.appsModel) return
                contextMenu.appsModel.hideApp(contextMenu.popupIndex)
                Plasmoid.configuration.hiddenApps = contextMenu.appsModel.hiddenApps
            }
        }
    }

    PlasmaComponents.Menu {
        id: bulkMenu

        onAboutToHide: contextMenu._trackClose()

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
            onClicked: contextMenu._bulkAddLauncher(Kicker.ContainmentInterface.TaskManager)
        }

        PlasmaComponents.MenuItem {
            icon.name: "desktop"
            text: i18ndp("dev.xarbit.appgrid",
                         "Add %1 to Desktop", "Add %1 to Desktop",
                         contextMenu.popupSelectedSids.length)
            onClicked: contextMenu._bulkAddLauncher(Kicker.ContainmentInterface.Desktop)
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
}
