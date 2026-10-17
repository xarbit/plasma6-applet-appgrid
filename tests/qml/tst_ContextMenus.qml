/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for FolderContextMenu.qml and RunnerContextMenu.qml: what they
    show for the folder or result they are opened for, and the requests
    their items send.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "ContextMenus"
    width: 400
    height: 400
    when: windowShown

    QtObject {
        id: foldersStub
        property var ungrouped: []
        property var global: ({ f1: true, f2: false })
        function isFolderGlobal(id) { return global[id] === true }
        function folderMembers(id) { return id === "f1" ? ["a", "b"] : [] }
        function setFolderGlobal(id, on) { global[id] = on }
        function ungroupFolder(id) { ungrouped.push(id) }
    }

    SignalSpy { id: openSpy; signalName: "openRequested" }
    SignalSpy { id: favSpy; signalName: "favoriteToggled" }
    SignalSpy { id: actionSpy; signalName: "actionTriggered" }

    function load(file, props) {
        var c = Qt.createComponent("../../package/contents/ui/widgets/" + file)
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        return createTemporaryObject(c, testCase, props)
    }

    function itemWithText(menu, text) {
        for (var i = 0; i < menu.count; ++i) {
            if (menu.itemAt(i).text === text)
                return menu.itemAt(i)
        }
        fail("no menu item " + text)
    }

    function test_folderMenuShowsTheFolder() {
        var m = load("FolderContextMenu.qml", { foldersModel: foldersStub })
        m.showFor("f1")
        compare(m.folderId, "f1")
        compare(m.folderGlobal, true)
        m.close()
        m.showFor("f2")
        compare(m.folderGlobal, false)
        m.close()
    }

    function test_folderMenuItemsRequest() {
        var m = load("FolderContextMenu.qml", { foldersModel: foldersStub })
        openSpy.target = m
        openSpy.clear()
        m.showFor("f1")
        m.itemAt(0).clicked()
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "f1")
        m.showFor("f1")
        m.itemAt(m.count - 1).clicked()
        compare(foldersStub.ungrouped.join(","), "f1")
    }

    function test_runnerMenuFavouriteAndActions() {
        var m = load("RunnerContextMenu.qml", {})
        favSpy.target = m; actionSpy.target = m
        favSpy.clear(); actionSpy.clear()
        m.showFor(3, [{ text: "Copy", icon: "edit-copy" }], "applications:org.kde.kcalc.desktop", false)
        compare(m.sourceIndex, 3)
        compare(m.isFavorite, false)
        // The favourite row, the separator and the action.
        tryCompare(m, "count", 3)
        itemWithText(m, "Add to Favorites").clicked()
        compare(favSpy.signalArguments[0][0], "applications:org.kde.kcalc.desktop")

        m.showFor(3, [{ text: "Copy", icon: "edit-copy" }], "applications:org.kde.kcalc.desktop", false)
        itemWithText(m, "Copy").clicked()
        compare(actionSpy.count, 1)
        compare(actionSpy.signalArguments[0][0], 3)
        compare(actionSpy.signalArguments[0][1], 0)
    }
}
