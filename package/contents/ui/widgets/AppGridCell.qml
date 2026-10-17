/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A cell of AppGridView: an app, a favourite (a KActivities row, keyed by
    its favourite id) or a favourites/menu folder. Resolves what the row is
    and shows a FolderCell or an AppCell for it; clicks go to the grid.
*/

import QtQuick
import dev.xarbit.appgrid.models

import "../js/favoriteid.js" as FavoriteId
import "../js/favoritevisual.js" as FavoriteVisual

Item {
    id: delegateRoot

    // The AppGridView this cell belongs to.
    required property var grid
    // The row, as the view's model gives it.
    required property var model
    width: grid.cellWidth
    height: grid.cellHeight

    // When favoritesActive, the grid is driven directly by
    // sharedFavoritesModel (KAStats), which exposes different role names
    // than AppFilterModel. Resolve the storage id from the model and
    // look up the matching AppModel row for non-essential fields
    // (genericName, comment, installSource, desktopFile, isNew).
    // Grid bound to the grouped model (issue #18): folder rows render a
    // FolderCell, app rows resolve via favoriteId exactly like the direct
    // KAStats grid does.
    readonly property bool _fromGrouped: grid._groupedGrid
    readonly property bool _isFolder: _fromGrouped && model.entryType === AbstractGroupedModel.Folder
    // "Shared" = a favourite app row keyed by favoriteId — true for both the
    // direct KAStats grid and the grouped model's app rows.
    readonly property bool _fromShared: (grid.favoritesActive
                                         && grid.sharedFavoritesModel
                                         && grid.model === grid.sharedFavoritesModel)
                                        || (_fromGrouped && !_isFolder)
    readonly property string _sid: _isFolder
        ? ""
        : (_fromShared ? FavoriteId.stripPrefix(model.favoriteId) : (model.storageId || ""))
    // Drag-to-folder target zone (#200): the folder's tile or the app's icon,
    // inset a little so it's a tighter target and more of the cell reorders.
    // Landing on it merges/adds; a drag can still pass over a folder.
    readonly property rect foldRect: {
        const r = (_isFolder && folderLoader.item) ? folderLoader.item.iconRect : iconDelegate.iconRect
        const m = r.width * grid.foldZoneInset
        return Qt.rect(r.x + m, r.y + m, r.width - 2 * m, r.height - 2 * m)
    }
    readonly property var _appData: _fromShared && grid.appsModel
                                    ? grid.appsModel.getByStorageId(_sid) : null
    // A text field of the app: from the app model for a favourite row (keyed by
    // its favourite id), else from the row itself.
    function _field(key) {
        return _fromShared ? (_appData ? _appData[key] || "" : "") : (model[key] || "")
    }
    // getByStorageId returns {} (not null) for an id the app model doesn't
    // know, so test the icon, not the object.
    readonly property bool _appKnown: !!(_appData && _appData.iconName)
    // KAStats name/icon fallback for a grouped app row the app model doesn't
    // know (a favourited KCM); the direct KAStats grid reads model.display /
    // model.decoration instead, which the grouped model can't provide.
    readonly property var _kvis: (_fromGrouped && !_appKnown && grid.sharedFavoritesModel)
                                 ? grid._favoriteVisual(_sid) : null
    // Member icon names for a folder's 2x2 preview, resolved via the app model.
    readonly property var _folderIcons: {
        if (!_isFolder)
            return []
        const members = model.folderMembers || []
        const icons = []
        for (let i = 0; i < members.length && icons.length < 4; ++i) {
            icons.push(FavoriteVisual.resolve(grid.appsModel, grid.sharedFavoritesModel,
                                              grid.favoriteIdRole, members[i], grid.defaultIcon).icon)
        }
        return icons
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
            memberIcons: delegateRoot._folderIcons
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
        appName: delegateRoot._fromShared
            ? ((delegateRoot._appKnown && delegateRoot._appData.name)
               || model.display
               || (delegateRoot._kvis && delegateRoot._kvis.display)
               || "")
            : (model.name || "")
        appIcon: delegateRoot._fromShared
            ? ((delegateRoot._appKnown && delegateRoot._appData.iconName)
               || model.decoration
               || (delegateRoot._kvis && delegateRoot._kvis.decoration)
               || grid.defaultIcon)
            : (model.iconName || grid.defaultIcon)
        displayIcon: delegateRoot._fromShared ? "" : grid.getDisplayIcon(model.index)
        appGenericName: delegateRoot._field("genericName")
        appComment: delegateRoot._field("comment")
        installSource: delegateRoot._field("installSource")
        hideLabel: grid.hideLabelsOnFavorites && grid.favoritesActive
        isCurrentItem: grid.currentIndex === model.index && grid.activeFocus
        newBadgeAllowed: !delegateRoot._fromShared
        storageId: delegateRoot._sid
        desktopFile: delegateRoot._field("desktopFile")
        gridRow: model.index

        onClicked: function(mouse) {
            const desktopFile = delegateRoot._field("desktopFile")
            if (mouse.button === Qt.RightButton) {
                // Selection persists across right-click so the menu can
                // surface "Add to selection" / "Remove from selection".
                grid.host.appMenuRequested(delegateRoot._sid, desktopFile, grid.selection.sidList())
                return
            }
            if (grid.multiSelectActive) {
                grid.currentIndex = model.index
                if (grid.selection.applyClickModifiers(mouse, model.index)) return
            }
            grid.selection.clear()
            if (delegateRoot._fromShared) {
                grid.launchFavorite(delegateRoot._sid)
            } else {
                grid.host.launchAppRequested(model.index)
            }
        }
        onShuffleRequested: {
            if (!delegateRoot._fromShared)
                grid.shuffleIcon(model.index)
        }
    }

    Connections {
        target: grid
        function onShakeAllIcons() { iconDelegate.shake() }
        function onShufflesUpdated() {
            iconDelegate.displayIcon = grid.getDisplayIcon(model.index)
        }
    }
}
