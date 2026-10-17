/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a folder: open it and launch all its apps (the caller sends
    them down the bulk launch path, so "open many at once?" still applies).
    Each kind of folder adds its own rows after these as the menu's children:
    a favourites folder (#18) its rename, activities and ungroup, a menu
    folder (#201) editing it in the menu editor.
*/

import QtQuick

AppGridMenu {
    id: folderMenu

    property string folderId: ""
    // (folderId) -> the ids "Launch All" starts; null: nothing to launch.
    property var appIdsOf: null
    // Read when the menu opens: a binding over appIdsOf(folderId) only re-runs
    // when folderId changes, so it went stale once the folder's apps changed.
    property list<string> appIds: []

    signal openRequested(string folderId)
    signal launchAllRequested(var appIds)

    function showFor(id) {
        folderId = id
        appIds = appIdsOf ? appIdsOf(id) : []
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
        enabled: folderMenu.appIds.length > 0
        onClicked: {
            folderMenu.launchAllRequested(folderMenu.appIds)
            folderMenu.close()
        }
    }
}
