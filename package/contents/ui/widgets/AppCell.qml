/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    An app icon cell in one of the launcher's grids (the app grid and the By
    Category view): the shared AppIconDelegate set up from its grid — the
    grid's icon and animation settings, drag source, new-app badge and
    multi-selection. The grid binds the app itself (name, icon, storageId,
    …), its index and whether it is the current cell, and handles clicks.
*/

import QtQuick

AppIconDelegate {
    id: cell

    // The grid this cell belongs to. Both grids expose the same names:
    // appsModel, iconSize, fontScale, hoverAnimation, shadowEnabled,
    // hoverHighlight, showTooltips, showNewAppBadge, dragSource, and the
    // selection (multiSelectActive, selectedSids, selectionAnchor,
    // selectionCount, selectedSidList(), selectedDesktopFileUrls(),
    // selectedIconNames()), plus _newAppsRevision for the badge.
    required property var view
    // The index the grid's selection anchor is compared against.
    property int cellIndex: -1
    // False where a badge makes no sense (a favourite row).
    property bool newBadgeAllowed: true

    iconGeneration: view.appsModel ? view.appsModel.iconGeneration : 0
    showTooltip: view.showTooltips
    iconSize: view.iconSize
    fontScale: view.fontScale
    hoverAnimation: view.hoverAnimation
    shadowEnabled: view.shadowEnabled
    hoverHighlight: view.hoverHighlight
    // Drag-out is allowed from every view (taskbar/panel/Dolphin pinning);
    // internal reorder is gated separately by the grid's drop handling.
    dragSource: view.dragSource

    isNew: {
        view._newAppsRevision // re-evaluate when the used apps change
        return newBadgeAllowed && view.showNewAppBadge && view.appsModel
            ? view.appsModel.isNewApp(storageId) : false
    }

    // Selection visuals: `selected` reads the grid's selection map, so toggling
    // any item re-evaluates every cell in one pass; `selectionAnchor` marks the
    // pivot of Shift+click / Shift+Arrow range selection.
    selected: view.multiSelectActive && !!view.selectedSids[storageId]
    selectionAnchor: view.multiSelectActive
                     && view.selectionAnchor === cellIndex
                     && view.selectionCount > 0
    // The whole selection rides along when a selected cell is dragged, so the
    // drag-out carries every selected app.
    multiSelectionSids: selected ? view.selectedSidList() : []
    multiSelectionUrls: selected ? view.selectedDesktopFileUrls() : []
    multiSelectionIcons: selected ? view.selectedIconNames() : []
}
