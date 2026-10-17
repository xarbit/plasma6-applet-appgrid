/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a favourites folder (#18): the shared Open / Launch All, then
    rename it, show it in every activity, or ungroup it (its members go back
    to loose favourites). Reads the folders from its AppContextMenu (`owner`).
*/

import QtQuick
import org.kde.plasma.components as PlasmaComponents

FolderContextMenu {
    id: menu

    // The AppContextMenu this menu belongs to.
    required property var owner

    readonly property var _folders: owner.favoritesGroupedModel
    // Whether the folder shows in every activity, read when it opens.
    property bool _global: false

    function showForFolder(id) {
        _global = _folders.isFolderGlobal(id)
        showFor(id)
    }

    appIdsOf: id => menu._folders ? menu._folders.folderMembers(id) : []
    onOpenRequested: folderId => menu.owner.openFolderRequested(folderId)
    onLaunchAllRequested: appIds => menu.owner.folderLaunchRequested(appIds)

    AppGridMenuItem {
        icon.name: "edit-rename"
        text: i18nd("dev.xarbit.appgrid", "Rename Folder…")
        onClicked: {
            menu.owner.renameFolderRequested(menu.folderId)
            menu.close()
        }
    }
    // Per-activity opt-in only: otherwise every folder is global anyway.
    AppGridMenuItem {
        visible: menu.owner.enableActivities
        checkable: true
        checked: menu._global
        text: i18nd("dev.xarbit.appgrid", "Show in all activities")
        onClicked: {
            if (menu._folders)
                menu._folders.setFolderGlobal(menu.folderId, !menu._global)
            menu.close()
        }
    }
    PlasmaComponents.MenuSeparator {}
    AppGridMenuItem {
        icon.name: "folder-remove"
        text: i18nd("dev.xarbit.appgrid", "Ungroup Folder")
        enabled: !!menu._folders
        onClicked: {
            menu._folders.ungroupFolder(menu.folderId)
            menu.close()
        }
    }
}
