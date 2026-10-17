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
    id: menu

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
        active: menu.owner.popupNonFavCount > 0
        delegate: AppGridMenuItem {
            icon.name: "bookmark-new"
            text: i18ndp("dev.xarbit.appgrid",
                         "Add %1 to Favorites", "Add %1 to Favorites",
                         menu.owner.popupNonFavCount)
            enabled: !menu.owner._favsLocked
            onClicked: menu._setFavorite(true)
        }
        onObjectAdded: (idx, obj) => menu.insertItem(0, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    Instantiator {
        active: menu.owner.popupFavCount > 0
        delegate: AppGridMenuItem {
            icon.name: "bookmark-remove"
            text: i18ndp("dev.xarbit.appgrid",
                         "Remove %1 from Favorites", "Remove %1 from Favorites",
                         menu.owner.popupFavCount)
            enabled: !menu.owner._favsLocked
            onClicked: menu._setFavorite(false)
        }
        onObjectAdded: (idx, obj) => menu.insertItem(menu.owner.popupNonFavCount > 0 ? 1 : 0, obj)
        onObjectRemoved: (idx, obj) => menu.removeItem(obj)
    }

    AppGridMenuItem {
        icon.name: "pin"
        text: i18ndp("dev.xarbit.appgrid",
                     "Pin %1 to Task Manager", "Pin %1 to Task Manager",
                     menu._sids.length)
        visible: menu.owner.popupCanPin
        onClicked: menu._desktopFiles().forEach(file => menu.owner.launcherActions.pinToTaskManager(file))
    }

    AppGridMenuItem {
        icon.name: "desktop"
        text: i18ndp("dev.xarbit.appgrid",
                     "Add %1 to Desktop", "Add %1 to Desktop",
                     menu._sids.length)
        visible: menu.owner.popupCanAddToDesktop
        onClicked: menu._desktopFiles().forEach(file => menu.owner.launcherActions.addToDesktop(file))
    }

    AppGridMenuItem {
        icon.name: "system-run"
        text: i18ndp("dev.xarbit.appgrid",
                     "Launch %1 application", "Launch %1 applications",
                     menu._sids.length)
        onClicked: menu.owner.bulkLaunchRequested(menu._sids)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: "edit-copy"
        text: i18ndp("dev.xarbit.appgrid",
                     "Copy %1 path", "Copy %1 paths",
                     menu._sids.length)
        onClicked: menu.owner._copyText(menu._desktopFiles().join("\n"))
    }

    AppGridMenuItem {
        icon.name: "view-hidden"
        text: i18ndp("dev.xarbit.appgrid",
                     "Hide %1 application", "Hide %1 applications",
                     menu._sids.length)
        onClicked: menu.owner.bulkHideRequested(menu._sids)
    }

    PlasmaComponents.MenuSeparator {}

    AppGridMenuItem {
        icon.name: "edit-select-none"
        text: i18nd("dev.xarbit.appgrid", "Remove from Selection")
        onClicked: menu.owner.toggleSelectionRequested(menu.owner.popupStorageId)
    }

    // "Add to Folder": the whole selection into a folder, or a new folder made
    // from it, favouriting any that aren't (#18).
    // Held as a property, not a child: a Menu child of a Menu becomes its
    // submenu at once, and this one is attached only when it applies.
    property var _addToFolderSubmenu: FolderTargetMenu {
        id: addToFolderSubmenu
        parent: menu.owner
        foldersModel: menu.owner.favoritesGroupedModel
        onFolderChosen: folderId => {
            const folders = menu.owner.favoritesGroupedModel
            for (let i = 0; i < menu._sids.length; ++i) {
                menu.owner.favoritesManager.ensureFavorite(menu._sids[i])
                folders.addToFolder(folderId, menu._sids[i])
            }
            menu.owner.clearSelectionRequested()
            menu.owner.close()
        }
        onNewFolderRequested: {
            for (let i = 0; i < menu._sids.length; ++i)
                menu.owner.favoritesManager.ensureFavorite(menu._sids[i])
            menu.owner.favoritesGroupedModel.createFolderFromMembers(
                menu._sids, i18nd("dev.xarbit.appgrid", "New Folder"))
            menu.owner.clearSelectionRequested()
            menu.owner.close()
        }
    }
}
