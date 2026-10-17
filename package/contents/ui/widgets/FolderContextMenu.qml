/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a folder: open it and launch all its apps (through the bulk
    launch path, so the "open many at once?" confirmation still applies).
    Each kind of folder adds its own rows after these as the menu's children:
    a favourites folder (#18) its rename, activities and ungroup, a menu
    folder (#201) editing it in the menu editor.
*/

import QtQuick

AppGridMenu {
    id: folderMenu

    property string folderId: ""
    // Whether the folder has apps to launch.
    property bool canLaunchAll: false

    signal openRequested(string folderId)
    signal launchAllRequested(string folderId)

    function showFor(id) {
        folderId = id
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
    AppGridMenuItem {
        icon.name: "system-run"
        text: i18nd("dev.xarbit.appgrid", "Launch All")
        enabled: folderMenu.canLaunchAll
        onClicked: {
            folderMenu.launchAllRequested(folderMenu.folderId)
            folderMenu.close()
        }
    }
}
