/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A cell of AppGridView: an app, a favourite (a KActivities row, keyed by
    its favourite id) or a favourites/menu folder. Resolves what the row is
    and shows a FolderCell or an AppCell for it; clicks go to the grid.
*/

import QtQuick
import dev.xarbit.appgrid.models


Item {
    id: delegateRoot

    // The AppGridView this cell belongs to.
    required property var grid
    // The row, as the view's model gives it.
    required property var model
    width: grid.cellWidth
    height: grid.cellHeight

    // A grouped grid (the favourites folders, the menu tree) holds app rows
    // and folder rows; its app rows give the same fields, under the same role
    // names, as the app model's rows. Their launch goes by id, not by row.
    readonly property bool _fromGrouped: grid._groupedGrid
    readonly property bool _isFolder: _fromGrouped && model.entryType === AbstractGroupedModel.Folder
    readonly property string _sid: _isFolder ? "" : (model.storageId || "")
    // Drag-to-folder target zone (#200): the folder's tile or the app's icon,
    // inset a little so it's a tighter target and more of the cell reorders.
    // Landing on it merges/adds; a drag can still pass over a folder.
    readonly property rect foldRect: {
        const r = (_isFolder && folderLoader.item) ? folderLoader.item.iconRect : iconDelegate.iconRect
        const m = r.width * grid.foldZoneInset
        return Qt.rect(r.x + m, r.y + m, r.width - 2 * m, r.height - 2 * m)
    }

    // Bounce this cell's app icon (Ctrl+D toggle feedback, #193). Folder rows
    // have no favourite to toggle, so they never get here.
    function bounceFeedback() { iconDelegate.bounceFeedback() }

    // A folder tile only for folder rows: most cells are apps (and the flat
    // All-apps grid has no folders), so don't build a hidden FolderCell in
    // every one of them.
    Loader {
        id: folderLoader
        anchors.fill: parent
        active: delegateRoot._isFolder
        sourceComponent: FolderCell {
            folderId: delegateRoot._isFolder ? (model.folderId || "") : ""
            folderName: delegateRoot._isFolder ? (model.display || "") : ""
            memberIcons: model.memberIcons || []
            cellStyle: grid.cellStyle
            hideLabel: grid.hideLabelsOnFavorites && grid.favoritesActive
            isCurrentItem: grid.currentIndex === model.index && grid.activeFocus
            dragSource: grid.dragSource
            gridRow: model.index
            // Record the tile as current so focus returns here when the folder
            // closes (e.g. Esc), not to the search field.
            onClicked: {
                grid.currentIndex = model.index
                grid.openFolderRequested(model.folderId)
            }
            onContextRequested: grid.folderContextMenuRequested(model.folderId)
        }
    }

    AppCell {
        id: iconDelegate
        anchors.fill: parent
        view: grid
        cellIndex: model.index
        visible: !delegateRoot._isFolder
        appName: model.name || ""
        appIcon: model.iconName || grid.defaultIcon
        // The shuffle swaps the app grid's icons only.
        displayIcon: delegateRoot._fromGrouped ? "" : grid.shuffle.iconAt(model.index)
        appGenericName: model.genericName || ""
        appComment: model.comment || ""
        installSource: model.installSource || ""
        hideLabel: grid.hideLabelsOnFavorites && grid.favoritesActive
        isCurrentItem: grid.currentIndex === model.index && grid.activeFocus
        newBadgeAllowed: !delegateRoot._fromGrouped
        storageId: delegateRoot._sid
        desktopFile: model.desktopFile || ""
        gridRow: model.index

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                // Selection persists across right-click so the menu can
                // surface "Add to selection" / "Remove from selection".
                grid.host.appMenuRequested(delegateRoot._sid, model.desktopFile || "", grid.selection.sidList())
                return
            }
            if (grid.multiSelectActive) {
                grid.currentIndex = model.index
                if (grid.selection.applyClickModifiers(mouse, model.index)) return
            }
            grid.selection.clear()
            if (delegateRoot._fromGrouped) {
                grid.launchFavorite(delegateRoot._sid)
            } else {
                grid.host.launchAppRequested(model.index)
            }
        }
        onShuffleRequested: {
            if (!delegateRoot._fromGrouped)
                grid.shuffle.shuffle(model.index)
        }
    }

    Connections {
        target: grid
        function onShakeAllIcons() { iconDelegate.shake() }
    }
}
