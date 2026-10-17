/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a multi-selection: favourite, pin, add to desktop, launch,
    copy the paths and hide all the selected apps, add them to a folder, or
    leave the selection. Reads the selection and the services from its
    AppContextMenu (`owner`). Launch and hide go up for their confirmation;
    the rest act at once (they are easy to undo).
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents

AppGridMenu {
    id: selectionMenu

    // The AppContextMenu this menu belongs to.
    required property var owner

    readonly property var _sids: owner.popupSelectedSids
    property bool _folderSubAdded: false

    // Attach "Add to Folder" when folders can be made here, then open. A
    // submenu's `visible` is its open-state, so it can't be bound.
    function showForSelection() {
        const want = owner._canCreateFolder && _sids.length > 0
        if (want !== _folderSubAdded) {
            if (want)
                addMenu(addToFolderSubmenu)
            else
                removeMenu(addToFolderSubmenu)
            _folderSubAdded = want
        }
        popup()
    }

    // The .desktop paths of the selected apps that have one.
    function _desktopFiles() {
        const apps = owner.appsModel
        const files = []
        for (let i = 0; apps && i < _sids.length; ++i) {
            const app = apps.getByStorageId(_sids[i])
            if (app && app.desktopFile)
                files.push(app.desktopFile)
        }
        return files
    }

    function _setFavorite(favorite) {
        const manager = owner.favoritesManager
        for (let i = 0; manager && i < _sids.length; ++i) {
            if (favorite)
                manager.ensureFavorite(_sids[i])
            else
                manager.removeFavorite(_sids[i])
        }
    }

    // Add-to-favourites goes first, remove-from-favourites below it.
    Instantiator {
        active: selectionMenu.owner.popupNonFavCount > 0
        delegate: AppGridMenuItem {
            icon.name: "bookmark-new"
            text: i18ndp("dev.xarbit.appgrid",
                         "Add %1 to Favorites", "Add %1 to Favorites",
                         selectionMenu.owner.popupNonFavCount)
            enabled: !selectionMenu.owner._favsLocked
            onClicked: selectionMenu._setFavorite(true)
        }
        onObjectAdded: (idx, obj) => selectionMenu.insertItem(0, obj)
        onObjectRemoved: (idx, obj) => selectionMenu.removeItem(obj)
    }

    Instantiator {
        active: selectionMenu.owner.popupFavCount > 0
        delegate: AppGridMenuItem {
            icon.name: "bookmark-remove"
            text: i18ndp("dev.xarbit.appgrid",
                         "Remove %1 from Favorites", "Remove %1 from Favorites",
                         selectionMenu.owner.popupFavCount)
            enabled: !selectionMenu.owner._favsLocked
            onClicked: selectionMenu._setFavorite(false)
        }
        onObjectAdded: (idx, obj) => selectionMenu.insertItem(selectionMenu.owner.popupNonFavCount > 0 ? 1 : 0, obj)
        onObjectRemoved: (idx, obj) => selectionMenu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: "pin"
        text: i18ndp("dev.xarbit.appgrid",
                     "Pin %1 to Task Manager", "Pin %1 to Task Manager",
                     selectionMenu._sids.length)
        visible: selectionMenu.owner.popupCanPin
        onClicked: selectionMenu._desktopFiles().forEach(file => selectionMenu.owner.launcherActions.pinToTaskManager(file))
    }

    AppGridMenuItem {
        icon.name: "desktop"
        text: i18ndp("dev.xarbit.appgrid",
                     "Add %1 to Desktop", "Add %1 to Desktop",
                     selectionMenu._sids.length)
        visible: selectionMenu.owner.popupCanAddToDesktop
        onClicked: selectionMenu._desktopFiles().forEach(file => selectionMenu.owner.launcherActions.addToDesktop(file))
    }

    AppGridMenuItem {
        icon.name: "system-run"
        text: i18ndp("dev.xarbit.appgrid",
                     "Launch %1 application", "Launch %1 applications",
                     selectionMenu._sids.length)
        onClicked: selectionMenu.owner.bulkLaunchRequested(selectionMenu._sids)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: "edit-copy"
        text: i18ndp("dev.xarbit.appgrid",
                     "Copy %1 path", "Copy %1 paths",
                     selectionMenu._sids.length)
        onClicked: selectionMenu.owner._copyText(selectionMenu._desktopFiles().join("\n"))
    }

    AppGridMenuItem {
        icon.name: "view-hidden"
        text: i18ndp("dev.xarbit.appgrid",
                     "Hide %1 application", "Hide %1 applications",
                     selectionMenu._sids.length)
        onClicked: selectionMenu.owner.bulkHideRequested(selectionMenu._sids)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: "edit-select-none"
        text: i18nd("dev.xarbit.appgrid", "Remove from Selection")
        onClicked: selectionMenu.owner.toggleSelectionRequested(selectionMenu.owner.popupStorageId)
    }

    // "Add to Folder": the whole selection into a folder, or a new folder made
    // from it, favouriting any that aren't (#18).
    // Held as a property, not a child: a Menu child of a Menu becomes its
    // submenu at once, and this one is attached only when it applies.
    property var _addToFolderSubmenu: FolderTargetMenu {
        id: addToFolderSubmenu
        parent: selectionMenu.owner
        foldersModel: selectionMenu.owner.favoritesGroupedModel
        onFolderChosen: folderId => {
            const folders = selectionMenu.owner.favoritesGroupedModel
            for (let i = 0; i < selectionMenu._sids.length; ++i) {
                selectionMenu.owner.favoritesManager.ensureFavorite(selectionMenu._sids[i])
                folders.addToFolder(folderId, selectionMenu._sids[i])
            }
            selectionMenu.owner.clearSelectionRequested()
            selectionMenu.owner.close()
        }
        onNewFolderRequested: {
            for (let i = 0; i < selectionMenu._sids.length; ++i)
                selectionMenu.owner.favoritesManager.ensureFavorite(selectionMenu._sids[i])
            selectionMenu.owner.favoritesGroupedModel.createFolderFromMembers(
                selectionMenu._sids, i18nd("dev.xarbit.appgrid", "New Folder"))
            selectionMenu.owner.clearSelectionRequested()
            selectionMenu.owner.close()
        }
    }
}
