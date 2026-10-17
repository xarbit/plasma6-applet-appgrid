/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for LauncherDialogs.qml: an accepted confirmation hands the host
    exactly what it was asked to confirm, and a rename reaches the folder
    model only with a non-empty name.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "LauncherDialogs"
    width: 400
    height: 400
    when: windowShown

    QtObject {
        id: foldersStub
        property var renamed: []
        function folderName(fid) { return "Old" }
        function renameFolder(fid, name) { renamed.push(fid + "=" + name) }
    }

    SignalSpy { id: launchSpy; signalName: "bulkLaunchAccepted" }
    SignalSpy { id: folderSpy; signalName: "folderLaunchAccepted" }
    SignalSpy { id: hideSpy; signalName: "bulkHideAccepted" }

    function make() {
        var c = Qt.createComponent("../../package/contents/ui/widgets/LauncherDialogs.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        var d = createTemporaryObject(c, testCase, { width: 400, height: 400, favoritesGroupedModel: foldersStub })
        launchSpy.target = d; folderSpy.target = d; hideSpy.target = d
        launchSpy.clear(); folderSpy.clear(); hideSpy.clear()
        return d
    }

    // The dialogs are popups, held in the item's data, not its children.
    function dialog(d, name) {
        for (var i = 0; i < d.data.length; ++i) {
            if (d.data[i].objectName === name)
                return d.data[i]
        }
        return null
    }

    function test_acceptedConfirmationsCarryTheirItems() {
        var d = make()
        d.confirmBulkLaunch(["a", "b", "c", "d"])
        dialog(d, "bulkLaunchDialog").accept()
        compare(launchSpy.count, 1)
        compare(launchSpy.signalArguments[0][0].length, 4)

        d.confirmFolderLaunch(["x", "y"])
        dialog(d, "folderLaunchDialog").accept()
        compare(folderSpy.count, 1)
        compare(folderSpy.signalArguments[0][0].join(","), "x,y")

        d.confirmBulkHide(["h"])
        dialog(d, "bulkHideDialog").accept()
        compare(hideSpy.count, 1)
        compare(hideSpy.signalArguments[0][0][0], "h")
    }

    function test_rejectedConfirmationDoesNothing() {
        var d = make()
        d.confirmBulkLaunch(["a"])
        dialog(d, "bulkLaunchDialog").reject()
        compare(launchSpy.count, 0)
    }

    function test_renameNeedsAName() {
        var d = make()
        foldersStub.renamed = []
        var rename = dialog(d, "renameFolderDialog")
        d.renameFolder("f1")
        var field = findChild(rename.contentItem, "nameField") || rename.contentItem
        compare(field.text, "Old")
        field.text = "  "
        rename.accept()
        compare(foldersStub.renamed.length, 0)

        d.renameFolder("f1")
        field.text = "Games"
        rename.accept()
        compare(foldersStub.renamed.join(","), "f1=Games")
    }
}
