/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared drag source for any app drag — internal favorites reorder and
    external drag-out (taskbar, panel, desktop, Dolphin). Mirrors Kickoff's
    `dragSource` (see plasma-desktop applets/kickoff/main.qml + BUG 449426):
    keeping the Drag attached on a stable Item — instead of on the recycled
    grid delegate — lets the platform DnD survive GridView re-layout while
    a drag is in flight.

    Usage from a delegate's DragHandler:

        dragSource.beginDrag(rootItem, iconItem, mimeData, handler)

    Helpers:
      isDragInFlight  — convenience for Drag.active, usable anywhere that
                        holds a reference to this source.
      isOwnDrag(drag) — true if the given DropArea drag originated here
                        (vs. an external drag like a .desktop from Dolphin).
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../js/constants.js" as Const

Item {
    id: source

    // The delegate Item currently being dragged. AppGridView's reorder
    // DropArea reads this via isOwnDrag(drag) and then inspects
    // `sourceItem.gridRow` to drive the reorder. The reference can become
    // null mid-drag (delegate recycling when the model swaps tabs), so the
    // identity bits are cached separately below.
    property Item sourceItem: null

    // Cached at beginDrag() so the drop handler can still identify what was
    // being dragged after the source delegate is gone.
    property string sourceStorageId: ""
    // Set when a folder cell is dragged (#18) — empty for app drags.
    property string sourceFolderId: ""
    property string sourceDesktopFile: ""

    // Cached selection at beginDrag() — populated only when the dragged item
    // was part of a multi-selection (length > 1). FavoritesReorderArea reads
    // this to skip internal reorder for multi-drags (drag-out only) and the
    // drop target sees the full URL list via Drag.mimeData "text/uri-list".
    property list<string> sourceStorageIds: []

    // True while the cursor is over the launcher's "drop here to remove" area
    // during a favorites drag-out (#193). The favorites delegate watches this to
    // swap its source cell for a remove (✕) marker, Kickoff-style.
    property bool dropWillRemove: false

    // True while the cursor sits over the Favorites tab with a drag of an app
    // that's already a favourite — the drop is forbidden (re-adding makes no
    // sense). The tab-hover sets it; the #193 remove area reads it and stands
    // down so nothing accepts → the platform shows the forbidden cursor and the
    // drop cancels.
    property bool blockedOnFavoritesTab: false

    // Fold target armed while a favourite hovers the centre of another favourite
    // (→ create folder) or a folder (→ add to it). The target cell watches these
    // to draw a merge highlight; cleared on drop/exit (issue #18).
    property string foldTargetStorageId: ""
    property string foldTargetFolderId: ""

    readonly property bool isDragInFlight: source.Drag.active

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction | Qt.LinkAction

    function isOwnDrag(drag) {
        return drag && drag.source === source
    }

    // Off-screen composite for multi-drag stack preview. Up to 3 icons drawn
    // diagonally offset (Dolphin's convention) plus a "+N" badge in the
    // bottom-right when the selection is larger. KDE doesn't expose this
    // helper publicly — every app that wants it (Dolphin, Kickoff, …)
    // reimplements locally, so do the same here.
    Item {
        id: stackComposite
        x: -9999  // off-screen, never visually rendered to the user
        width: 64
        height: 64
        visible: true
        property list<string> icons: []

        Repeater {
            model: Math.min(stackComposite.icons.length, 3)
            delegate: Kirigami.Icon {
                required property int index
                x: index * 8
                y: index * 8
                width: 48
                height: 48
                source: stackComposite.icons[index] || Const.DEFAULT_ICON
            }
        }

        Rectangle {
            visible: stackComposite.icons.length > 3
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, countLabel.contentWidth + Kirigami.Units.largeSpacing)
            height: Kirigami.Units.iconSizes.small
            radius: height / 2
            color: Kirigami.Theme.highlightColor
            border.color: Kirigami.Theme.backgroundColor
            border.width: 1
            Text {
                id: countLabel
                anchors.centerIn: parent
                text: "+" + (stackComposite.icons.length - 3)
                color: Kirigami.Theme.highlightedTextColor
                font.pixelSize: parent.height * 0.65
                font.bold: true
            }
        }
    }

    // Cache the dragged delegate's identity and go live. Shared by the single
    // and multi grab callbacks.
    function _activate(delegate, mimeData, imageUrl, sids) {
        source.sourceItem = delegate
        source.sourceStorageId = delegate.storageId || ""
        source.sourceFolderId = delegate.folderId || ""
        source.sourceDesktopFile = delegate.desktopFile || ""
        source.sourceStorageIds = sids
        source.Drag.imageSource = imageUrl
        source.Drag.mimeData = mimeData
        source.Drag.active = true
    }

    // Begin a drag on behalf of `delegate` (the delegate Item being dragged),
    // taking the drag pixmap from `iconItem` (single-item) or rendering a
    // stacked preview (multi-item) and advertising `mimeData`. The `handler`
    // parameter is the originating DragHandler — its active flag is re-
    // checked once grabToImage completes so we don't activate a stale drag
    // if the user released before the snapshot was ready.
    function beginDrag(delegate, iconItem, mimeData, handler, sids, iconNames) {
        const multi = sids && sids.length > 1
        if (multi && iconNames && iconNames.length > 1) {
            stackComposite.icons = iconNames
            // Defer the grab one tick so Kirigami.Icon's source resolution
            // has time to populate. If icons are missing from the theme cache
            // the rendered pixmap may show fallback glyphs — acceptable.
            Qt.callLater(function() {
                stackComposite.grabToImage(function(result) {
                    if (!handler.active) {
                        stackComposite.icons = []
                        return
                    }
                    source._activate(delegate, mimeData, result.url, sids)
                    stackComposite.icons = []
                })
            })
            return
        }
        iconItem.grabToImage(function(result) {
            if (!handler.active) return
            source._activate(delegate, mimeData, result.url, sids && sids.length > 1 ? sids : [])
        })
    }

    // Tear down the drag state. Called from a handler's activeChanged when
    // the drag ends (drop or cancel).
    function endDrag() {
        source.Drag.active = false
        source.Drag.imageSource = ""
        source.sourceItem = null
        source.sourceStorageId = ""
        source.sourceFolderId = ""
        source.sourceDesktopFile = ""
        source.sourceStorageIds = []
        source.dropWillRemove = false
        source.blockedOnFavoritesTab = false
        source.foldTargetStorageId = ""
        source.foldTargetFolderId = ""
    }
}
