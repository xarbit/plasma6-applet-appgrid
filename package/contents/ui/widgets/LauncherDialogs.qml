/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The launcher's dialogs: confirming a bulk launch, a folder's "Launch All"
    and a bulk hide, and renaming a favourites folder. The host decides what
    an accepted confirmation does.
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    // For the folder rename (#18); null disables it.
    property var favoritesGroupedModel: null

    signal bulkLaunchAccepted(var sids)
    signal folderLaunchAccepted(var members)
    signal bulkHideAccepted(var sids)

    function confirmBulkLaunch(sids) {
        bulkLaunchDialog.pendingSids = sids
        bulkLaunchDialog.open()
    }
    function confirmFolderLaunch(members) {
        folderLaunchDialog.pendingMembers = members
        folderLaunchDialog.open()
    }
    function confirmBulkHide(sids) {
        bulkHideDialog.pendingSids = sids
        bulkHideDialog.open()
    }
    function renameFolder(folderId) {
        renameFolderDialog.openFor(folderId)
    }

    Kirigami.PromptDialog {
        id: bulkLaunchDialog
        objectName: "bulkLaunchDialog"
        property list<string> pendingSids: []
        title: i18nd("dev.xarbit.appgrid", "Launch all selected?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Open %1 application at once?",
            "Open %1 applications at once?",
            pendingSids.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.bulkLaunchAccepted(pendingSids)
    }

    // Folder "Launch All" confirm — like bulkLaunchDialog, but the host
    // launches each member favourite-aware (handles KCMs) (#18).
    Kirigami.PromptDialog {
        id: folderLaunchDialog
        objectName: "folderLaunchDialog"
        property var pendingMembers: []
        title: i18nd("dev.xarbit.appgrid", "Launch all in folder?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Open %1 application at once?",
            "Open %1 applications at once?",
            pendingMembers.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.folderLaunchAccepted(pendingMembers)
    }

    Kirigami.PromptDialog {
        id: bulkHideDialog
        objectName: "bulkHideDialog"
        property list<string> pendingSids: []
        title: i18nd("dev.xarbit.appgrid", "Hide selected applications?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Hide %1 application from AppGrid? You can unhide it later in Settings → Hidden Applications.",
            "Hide %1 applications from AppGrid? You can unhide them later in Settings → Hidden Applications.",
            pendingSids.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: root.bulkHideAccepted(pendingSids)
    }

    // Folder rename (#18).
    Kirigami.PromptDialog {
        id: renameFolderDialog
        objectName: "renameFolderDialog"
        property string folderId: ""
        title: i18nd("dev.xarbit.appgrid", "Rename Folder")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel

        function openFor(fid) {
            folderId = fid
            nameField.text = root.favoritesGroupedModel
                ? root.favoritesGroupedModel.folderName(fid) : ""
            open()
            nameField.forceActiveFocus()
            nameField.selectAll()
        }
        onAccepted: {
            const name = nameField.text.trim()
            if (root.favoritesGroupedModel && folderId.length > 0 && name.length > 0)
                root.favoritesGroupedModel.renameFolder(folderId, name)
        }

        PlasmaComponents.TextField {
            id: nameField
            objectName: "nameField"
            onAccepted: renameFolderDialog.accept()
        }
    }
}
