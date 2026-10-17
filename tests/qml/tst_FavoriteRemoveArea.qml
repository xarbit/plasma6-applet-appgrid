/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for FavoriteRemoveArea.qml's decisions: which dragged items a
    drop would remove (only the launcher's own drags, only favourites, and
    nothing while the drag is blocked over the Favorites tab), and a dragged
    folder.
*/

import QtQuick
import QtTest

TestCase {
    name: "FavoriteRemoveArea"

    QtObject {
        id: favoritesStub
        function isFavorite(id) { return id === "applications:kate.desktop" || id === "applications:gimp.desktop" }
    }
    QtObject {
        id: sourceStub
        property bool own: true
        property bool blockedOnFavoritesTab: false
        property var sourceStorageIds: []
        property string sourceStorageId: ""
        property string sourceFolderId: ""
        property bool dropWillRemove: false
        function isOwnDrag(drag) { return own }
    }

    function make() {
        var c = Qt.createComponent("../../package/contents/ui/widgets/FavoriteRemoveArea.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        return createTemporaryObject(c, null, { dragSource: sourceStub, favoritesModel: favoritesStub })
    }

    function init() {
        sourceStub.own = true
        sourceStub.blockedOnFavoritesTab = false
        sourceStub.sourceStorageIds = []
        sourceStub.sourceStorageId = ""
        sourceStub.sourceFolderId = ""
    }

    function test_onlyFavoritesAreRemovable() {
        var area = make()
        sourceStub.sourceStorageIds = ["kate.desktop", "dolphin.desktop", "gimp.desktop"]
        compare(area._favoriteSids({}).join(","), "kate.desktop,gimp.desktop")
        verify(area._removable({}))
    }

    function test_singleDragUsesTheSourceId() {
        var area = make()
        sourceStub.sourceStorageId = "kate.desktop"
        compare(area._favoriteSids({}).join(","), "kate.desktop")
        sourceStub.sourceStorageId = "dolphin.desktop"
        verify(!area._removable({}))
    }

    function test_foreignOrBlockedDragsRemoveNothing() {
        var area = make()
        sourceStub.sourceStorageId = "kate.desktop"
        sourceStub.sourceFolderId = "f1"
        sourceStub.own = false
        verify(!area._removable({}))
        sourceStub.own = true
        sourceStub.blockedOnFavoritesTab = true
        verify(!area._removable({}))
    }

    function test_folderDrag() {
        var area = make()
        sourceStub.sourceFolderId = "f1"
        compare(area._folderId({}), "f1")
        verify(area._removable({}))
    }
}
