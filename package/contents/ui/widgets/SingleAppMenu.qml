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
    id: appMenu

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
            // array every open would churn the Instantiator and corrupt the appMenu.
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
        model: appMenu.owner.popupActions
        delegate: AppGridMenuItem {
            required property var modelData
            icon.name: modelData.icon || ""
            text: modelData.text
            onClicked: {
                appMenu.owner.launchService.launchAction(appMenu.owner.popupStorageId, modelData.name)
                appMenu.close()
            }
        }
        onObjectAdded: (idx, obj) => appMenu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => appMenu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: appMenu.owner.popupIsFavorite ? "bookmark-remove" : "bookmark-new"
        text: appMenu.owner.popupIsFavorite
              ? i18nd("dev.xarbit.appgrid", "Remove from Favorites")
              : i18nd("dev.xarbit.appgrid", "Add to Favorites")
        enabled: !appMenu.owner._favsLocked
        onClicked: {
            if (appMenu.owner.popupStorageId)
                appMenu.owner._toggleFavorite(FavoriteId.toPrefixed(appMenu.owner.popupStorageId))
        }
    }

    // Take the app out of its folder (it stays a favourite) — only while it is
    // in one (#18).
    Instantiator {
        active: appMenu.owner.popupInFolder
        delegate: AppGridMenuItem {
            icon.name: "folder-remove"
            text: i18nd("dev.xarbit.appgrid", "Remove from Folder")
            onClicked: appMenu.owner.favoritesManager.removeFromAnyFolder(appMenu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => appMenu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => appMenu.removeItem(obj)
    }

    // Only where the view has a multi-selection (not the search results).
    Instantiator {
        active: appMenu.owner.popupCanSelect
        delegate: AppGridMenuItem {
            icon.name: appMenu.owner.popupIsSelected ? "edit-select-none" : "edit-select-all"
            text: appMenu.owner.popupIsSelected
                  ? i18nd("dev.xarbit.appgrid", "Remove from Selection")
                  : i18nd("dev.xarbit.appgrid", "Add to Selection")
            onClicked: appMenu.owner.toggleSelectionRequested(appMenu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => appMenu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => appMenu.removeItem(obj)
    }

    Instantiator {
        active: appMenu.owner.popupCanSelect
        delegate: PlasmaComponents.MenuSeparator {}
        onObjectAdded: (idx, obj) => appMenu.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => appMenu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: "pin"
        text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        visible: appMenu.owner.popupCanPin
        onClicked: appMenu.owner.launcherActions.pinToTaskManager(appMenu.owner.popupDesktopFile)
    }

    AppGridMenuItem {
        icon.name: "desktop"
        text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
        visible: appMenu.owner.popupCanAddToDesktop
        onClicked: appMenu.owner.launcherActions.addToDesktop(appMenu.owner.popupDesktopFile)
    }

    AppGridMenuItem {
        icon.name: "document-edit"
        text: i18nd("dev.xarbit.appgrid", "Edit Application")
        onClicked: appMenu.owner.launcherActions.editMenuItem(appMenu.owner.popupStorageId)
    }

    Instantiator {
        active: appMenu.owner.popupCanManageInDiscover
        delegate: AppGridMenuItem {
            icon.name: "plasmadiscover"
            text: i18nd("dev.xarbit.appgrid", "Manage in Discover…")
            onClicked: appMenu.owner.systemActions.openInDiscover(appMenu.owner.popupStorageId)
        }
        onObjectAdded: (idx, obj) => appMenu.addItem(obj)
        onObjectRemoved: (idx, obj) => appMenu.removeItem(obj)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: appMenu.owner.popupIsHidden ? "view-visible" : "view-hidden"
        text: appMenu.owner.popupIsHidden
              ? i18nd("dev.xarbit.appgrid", "Unhide Application")
              : i18nd("dev.xarbit.appgrid", "Hide Application")
        onClicked: {
            const apps = appMenu.owner.appsModel
            const sid = appMenu.owner.popupStorageId
            if (!apps || !sid)
                return
            if (appMenu.owner.popupIsHidden)
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
        parent: appMenu.owner
        activities: appMenu._activities
        linkedActivities: appMenu._linkedActivities
        isFavorite: appMenu.owner.popupIsFavorite
        onChosen: activityIds => {
            if (appMenu.owner.sharedFavoritesModel) {
                appMenu.owner.sharedFavoritesModel.setLinkedActivities(
                    FavoriteId.toPrefixed(appMenu.owner.popupStorageId), activityIds)
            }
            appMenu.owner.close()
        }
    }

    // "Add to Folder": adds (and favourites, if needed) the app (#18).
    property var _addToFolderSubmenu: FolderTargetMenu {
        id: addToFolderSubmenu
        parent: appMenu.owner
        foldersModel: appMenu.owner.favoritesGroupedModel
        disabledMemberSid: appMenu.owner.popupStorageId
        onFolderChosen: folderId => {
            appMenu.owner.favoritesManager.ensureFavorite(appMenu.owner.popupStorageId)
            appMenu.owner.favoritesGroupedModel.addToFolder(folderId, appMenu.owner.popupStorageId)
            appMenu.owner.close()
        }
        onNewFolderRequested: {
            appMenu.owner.favoritesManager.ensureFavorite(appMenu.owner.popupStorageId)
            appMenu.owner.favoritesGroupedModel.createFolderFromMembers([appMenu.owner.popupStorageId])
            appMenu.owner.close()
        }
    }
}
