/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a favourites folder (#18): open it, launch all its apps,
    rename it, show it in every activity, or ungroup it (its members return
    to loose favourites).
*/

import QtQuick
import org.kde.plasma.components as PlasmaComponents

AppGridMenu {
    id: folderMenu

    // FavoritesGroupedModel.
    property var foldersModel: null
    // Per-activity favourites on; otherwise every folder is global anyway.
    property bool enableActivities: false

    property string folderId: ""
    property bool folderGlobal: false

    signal openRequested(string folderId)
    signal launchAllRequested(string folderId)
    signal renameRequested(string folderId)

    function showFor(id) {
        folderId = id
        folderGlobal = foldersModel ? foldersModel.isFolderGlobal(id) : false
        popup()
    }

    AppGridMenuItem {
        icon.name: "folder-open"
        text: i18nd("dev.xarbit.appgrid", "Open Folder")
        onClicked: {
            folderMenu.openRequested(folderMenu.folderId)
            folderMenu.close()
        }
    }
    // Launch every app in the folder, through the same bulk-launch path (so
    // the "open many at once?" confirm threshold still applies).
    AppGridMenuItem {
        icon.name: "system-run"
        text: i18nd("dev.xarbit.appgrid", "Launch All")
        enabled: folderMenu.foldersModel
                 && folderMenu.foldersModel.folderMembers(folderMenu.folderId).length > 0
        onClicked: {
            folderMenu.launchAllRequested(folderMenu.folderId)
            folderMenu.close()
        }
    }
    AppGridMenuItem {
        icon.name: "edit-rename"
        text: i18nd("dev.xarbit.appgrid", "Rename Folder…")
        onClicked: {
            folderMenu.renameRequested(folderMenu.folderId)
            folderMenu.close()
        }
    }
    AppGridMenuItem {
        visible: folderMenu.enableActivities
        checkable: true
        checked: folderMenu.folderGlobal
        text: i18nd("dev.xarbit.appgrid", "Show in all activities")
        onClicked: {
            if (folderMenu.foldersModel)
                folderMenu.foldersModel.setFolderGlobal(folderMenu.folderId, !folderMenu.folderGlobal)
            folderMenu.close()
        }
    }
    PlasmaComponents.MenuSeparator {}
    AppGridMenuItem {
        icon.name: "folder-remove"
        text: i18nd("dev.xarbit.appgrid", "Ungroup Folder")
        enabled: folderMenu.foldersModel
        onClicked: {
            folderMenu.foldersModel.ungroupFolder(folderMenu.folderId)
            folderMenu.close()
        }
    }
}
