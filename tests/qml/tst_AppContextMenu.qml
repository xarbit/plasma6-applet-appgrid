/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for AppContextMenu.qml: what the menu reads about the app when it
    opens. "Remove from Folder" follows the app's folder each time, not the
    folder it was in when the menu last opened on it.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/widgets"

TestCase {
    id: testCase
    name: "AppContextMenu"
    width: 400
    height: 400
    when: windowShown

    // sid -> folder id, read by the grouped-model stub.
    property var folderOf: ({})

    QtObject {
        id: groupedStub
        property bool editable: true
        property bool canGoBack: false
        property var favoriteFolders: []
        function folderOfMember(sid) { return testCase.folderOf[sid] || "" }
        function folderMembers(folderId) { return [] }
    }
    QtObject {
        id: managerStub
        property var sharedFavoritesModel: null
        property var favoritesGroupedModel: groupedStub
    }

    Component {
        id: menuComponent
        AppContextMenu {
            favoritesManager: managerStub
            foldersEnabled: true
            appActions: sid => []
            launchAppAction: (sid, actionName) => {}
            canManageInDiscover: sid => false
            openInDiscover: sid => {}
            pinToTaskManager: desktopFile => {}
            addToDesktop: desktopFile => {}
            canPinToTaskManager: () => false
            canAddToDesktop: () => false
            editApplication: sid => {}
            runRunnerAction: (row, action) => {}
        }
    }

    function test_removeFromFolderFollowsTheFolderOnOpen() {
        var menu = createTemporaryObject(menuComponent, testCase)
        verify(menu)
        testCase.folderOf = { a: "f1" }
        menu.showForApp("a", "", [])
        verify(menu.popupInFolder, "in a folder")
        menu.close()
        // The same app again, after it left the folder: past the reopen guard.
        wait(300)
        testCase.folderOf = {}
        menu.showForApp("a", "", [])
        verify(!menu.popupInFolder, "no longer in a folder")
        menu.close()
    }

    function test_noFolderRowWithFoldersOff() {
        var menu = createTemporaryObject(menuComponent, testCase, { foldersEnabled: false })
        testCase.folderOf = { a: "f1" }
        menu.showForApp("a", "", [])
        verify(!menu.popupInFolder)
        menu.close()
    }
}
