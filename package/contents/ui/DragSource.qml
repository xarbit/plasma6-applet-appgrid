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
    property string sourceDesktopFile: ""

    readonly property bool isDragInFlight: source.Drag.active

    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction | Qt.LinkAction

    function isOwnDrag(drag) {
        return drag && drag.source === source
    }

    // Begin a drag on behalf of `delegate` (the delegate Item being dragged),
    // taking the drag pixmap from `iconItem` and advertising `mimeData`. The
    // `handler` parameter is the originating DragHandler — its active flag
    // is re-checked once grabToImage completes so we don't activate a stale
    // drag if the user released before the snapshot was ready.
    function beginDrag(delegate, iconItem, mimeData, handler) {
        iconItem.grabToImage(function(result) {
            if (!handler.active) return
            source.sourceItem = delegate
            source.sourceStorageId = delegate.storageId || ""
            source.sourceDesktopFile = delegate.desktopFile || ""
            source.Drag.imageSource = result.url
            source.Drag.mimeData = mimeData
            source.Drag.active = true
        })
    }

    // Tear down the drag state. Called from a handler's activeChanged when
    // the drag ends (drop or cancel).
    function endDrag() {
        source.Drag.active = false
        source.Drag.imageSource = ""
        source.sourceItem = null
        source.sourceStorageId = ""
        source.sourceDesktopFile = ""
    }
}
