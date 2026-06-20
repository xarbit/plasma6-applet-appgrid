/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A reusable "Add to Folder" submenu: lists the current favourite folders plus
    a "New Folder…" entry, and reports which target the user picked. Used for both
    the single-app and multi-select context menus, which differ only in what they
    do with the chosen folder (#18).
*/

import QtQuick

import org.kde.plasma.components as PlasmaComponents

AppGridMenu {
    id: root

    title: i18nd("dev.xarbit.appgrid", "Add to Folder")

    // The grouped model exposing favoriteFolders + folderOfMember().
    property var foldersModel: null
    // When set, a folder this sid already belongs to is disabled — a single app
    // can't be re-added to its own folder, but can still be moved to another.
    property string disabledMemberSid: ""

    signal folderChosen(string folderId)
    signal newFolderRequested()

    Instantiator {
        model: root.foldersModel ? root.foldersModel.favoriteFolders : []
        delegate: PlasmaComponents.MenuItem {
            required property int index
            property string folderId: ""
            icon.name: "folder"
            enabled: !root.disabledMemberSid || !root.foldersModel
                     || root.foldersModel.folderOfMember(root.disabledMemberSid) !== folderId
            // Read the folder by index off the model and capture once: an
            // Instantiator item loses its modelData when insertItem reparents it.
            Component.onCompleted: {
                const f = root._folderAt(index)
                if (f) {
                    folderId = f.id || ""
                    text = f.name || i18nd("dev.xarbit.appgrid", "Folder")
                }
            }
            onClicked: root.folderChosen(folderId)
        }
        onObjectAdded: (idx, obj) => root.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => root.removeItem(obj)
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        icon.name: "folder-new"
        text: i18nd("dev.xarbit.appgrid", "New Folder…")
        onClicked: root.newFolderRequested()
    }

    function _folderAt(index) {
        const folders = root.foldersModel ? root.foldersModel.favoriteFolders : []
        return (index >= 0 && index < folders.length) ? folders[index] : null
    }
}
