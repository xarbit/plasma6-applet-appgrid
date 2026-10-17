/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of one app: its jump-list actions, favourite and folder rows,
    selection, pin / desktop / edit / Discover, and hiding it. Reads the app it
    was opened for and the services from its AppContextMenu (`owner`).
    Conditional rows use an Instantiator rather than `visible: false`, which
    leaves a blank row in a PlasmaComponents.Menu.
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import "../js/favoriteid.js" as FavoriteId

AppGridMenu {
    id: menu

    // The AppContextMenu this menu belongs to.
    required property var owner

    property bool _folderSubAdded: false
    property bool _activitiesSubAdded: false
    // Id-set of the activities currently built into the submenu, so its item
    // list is only rebuilt when the set changes (not on every open).
    property string _activitiesSig: ""
    // The activity submenu's state for the app.
    property var _activities: []
    property var _linkedActivities: []

    // Attach the submenus that apply to the app, then open. A submenu's
    // `visible` is its open-state, so it can't be bound: add or remove it.
    function showForApp() {
        const sid = owner.popupStorageId
        // Any app can be added to a folder; a non-favourite is favourited in
        // the process.
        const wantFolderSub = owner._canCreateFolder && sid.length > 0
        if (wantFolderSub !== _folderSubAdded) {
            if (wantFolderSub)
                addMenu(addToFolderSubmenu)
            else
                removeMenu(addToFolderSubmenu)
            _folderSubAdded = wantFolderSub
        }

        // "Show in Favorites" when there is more than one activity. Picking an
        // activity for a non-favourite favourites it there.
        const favorites = owner.sharedFavoritesModel
        const acts = owner.enableActivities && favorites ? favorites.activities() : []
        const wantActivitiesSub = acts.length > 1
        if (wantActivitiesSub) {
            // Rebuild the items only when the activity set changes; a fresh
            // array every open would churn the Instantiator and corrupt the menu.
            const sig = acts.map(a => a.id).join("\n")
            if (sig !== _activitiesSig) {
                _activities = acts
                _activitiesSig = sig
            }
            _linkedActivities = owner.popupIsFavorite
                ? favorites.linkedActivitiesFor(FavoriteId.toPrefixed(sid)) : []
        }
        if (wantActivitiesSub !== _activitiesSubAdded) {
            if (wantActivitiesSub)
                addMenu(activitiesSubmenu)
            else
                removeMenu(activitiesSubmenu)
            _activitiesSubAdded = wantActivitiesSub
        }
        popup()
    }

    Instantiator {
        model: menu.owner.popupActions
        delegate: AppGridMenuItem {
            required property var modelData
            icon.name: modelData.icon || ""
            text: modelData.text
            onClicked: {
                menu.owner.launchService.launchAction(menu.owner.popupStorageId, modelData.name)
                menu.close()
            }
        }
        onObjectAdded: (idx, obj) => menu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: menu.owner.popupIsFavorite ? "bookmark-remove" : "bookmark-new"
        text: menu.owner.popupIsFavorite
              ? i18nd("dev.xarbit.appgrid", "Remove from Favorites")
              : i18nd("dev.xarbit.appgrid", "Add to Favorites")
        enabled: !menu.owner._favsLocked
        onClicked: {
            if (menu.owner.popupStorageId)
                menu.owner._toggleFavorite(FavoriteId.toPrefixed(menu.owner.popupStorageId))
        }
    }

    // Take the app out of its folder (it stays a favourite) — only while it is
    // in one (#18).
    Instantiator {
        active: menu.owner.popupInFolder
        delegate: AppGridMenuItem {
            icon.name: "folder-remove"
            text: i18nd("dev.xarbit.appgrid", "Remove from Folder")
            onClicked: menu.owner.favoritesManager.removeFromAnyFolder(menu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => menu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    // Only where the view has a multi-selection (not the search results).
    Instantiator {
        active: menu.owner.popupCanSelect
        delegate: AppGridMenuItem {
            icon.name: menu.owner.popupIsSelected ? "edit-select-none" : "edit-select-all"
            text: menu.owner.popupIsSelected
                  ? i18nd("dev.xarbit.appgrid", "Remove from Selection")
                  : i18nd("dev.xarbit.appgrid", "Add to Selection")
            onClicked: menu.owner.toggleSelectionRequested(menu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => menu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    Instantiator {
        active: menu.owner.popupCanSelect
        delegate: PlasmaComponents.MenuSeparator {}
        onObjectAdded: (idx, obj) => menu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: "pin"
        text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        visible: menu.owner.popupCanPin
        onClicked: menu.owner.launcherActions.pinToTaskManager(menu.owner.popupDesktopFile)
    }

    AppGridMenuItem {
        icon.name: "desktop"
        text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
        visible: menu.owner.popupCanAddToDesktop
        onClicked: menu.owner.launcherActions.addToDesktop(menu.owner.popupDesktopFile)
    }

    AppGridMenuItem {
        icon.name: "document-edit"
        text: i18nd("dev.xarbit.appgrid", "Edit Application")
        onClicked: menu.owner.launcherActions.editMenuItem(menu.owner.popupStorageId)
    }

    Instantiator {
        active: menu.owner.popupCanManageInDiscover
        delegate: AppGridMenuItem {
            icon.name: "plasmadiscover"
            text: i18nd("dev.xarbit.appgrid", "Manage in Discover…")
            onClicked: menu.owner.systemActions.openInDiscover(menu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => menu.addItem(obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: menu.owner.popupIsHidden ? "view-visible" : "view-hidden"
        text: menu.owner.popupIsHidden
              ? i18nd("dev.xarbit.appgrid", "Unhide Application")
              : i18nd("dev.xarbit.appgrid", "Hide Application")
        onClicked: {
            const apps = menu.owner.appsModel
            const sid = menu.owner.popupStorageId
            if (!apps || !sid)
                return
            if (menu.owner.popupIsHidden)
                apps.unhideApp(sid)
            else
                apps.hideByStorageId(sid)
        }
    }

    // "Show in Favorites": pins the favourite to the chosen activities (the
    // state lives in KActivities, shared by every launcher).
    // Submenus are held as properties, not children: a Menu child of a Menu
    // becomes its submenu at once, and these are attached only when they apply.
    property var _activitiesSubmenu: ActivityFavoritesMenu {
        id: activitiesSubmenu
        parent: menu.owner
        activities: menu._activities
        linkedActivities: menu._linkedActivities
        isFavorite: menu.owner.popupIsFavorite
        onChosen: activityIds => {
            if (menu.owner.sharedFavoritesModel) {
                menu.owner.sharedFavoritesModel.setLinkedActivities(
                    FavoriteId.toPrefixed(menu.owner.popupStorageId), activityIds)
            }
            menu.owner.close()
        }
    }

    // "Add to Folder": adds (and favourites, if needed) the app (#18).
    property var _addToFolderSubmenu: FolderTargetMenu {
        id: addToFolderSubmenu
        parent: menu.owner
        foldersModel: menu.owner.favoritesGroupedModel
        disabledMemberSid: menu.owner.popupStorageId
        onFolderChosen: folderId => {
            menu.owner.favoritesManager.ensureFavorite(menu.owner.popupStorageId)
            menu.owner.favoritesGroupedModel.addToFolder(folderId, menu.owner.popupStorageId)
            menu.owner.close()
        }
        onNewFolderRequested: {
            menu.owner.favoritesManager.ensureFavorite(menu.owner.popupStorageId)
            menu.owner.favoritesGroupedModel.createFolderFromMembers([menu.owner.popupStorageId])
            menu.owner.close()
        }
    }
}
