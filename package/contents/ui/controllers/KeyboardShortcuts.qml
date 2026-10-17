/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Grid-scoped keyboard shortcuts for AppGridView. The home for any new
    Shortcut declarations that act on the grid; per-key navigation handlers
    (`Keys.on*Pressed`) stay on the GridView itself because they're bound
    to keyboard focus.

    Currently:
      Ctrl+Shift+Arrow  — reorder the highlighted favorite by one cell

    Usage:
        KeyboardShortcuts { gridView: gridView }
*/

import QtQuick

Item {
    id: shortcuts

    // The owning AppGridView. The reorder shortcuts move the highlighted entry
    // in its grouped favourites model (the stored order, folders included);
    // we read currentIndex, count, effectiveColumns, model, groupedModel,
    // groupEditable and favoritesActive.
    required property GridView gridView

    required property bool sortFavoritesAlphabetically

    // --- Favorites reorder (Ctrl+Shift+Arrow) ---

    // Reactive so the Shortcut `enabled` bindings below re-evaluate when any
    // dependency changes — an imperative function call wouldn't track these
    // inside a binding.
    readonly property bool _canReorder: gridView.favoritesActive
               && gridView.groupEditable
               && !!gridView.groupedModel
               && gridView.model === gridView.groupedModel
               && !sortFavoritesAlphabetically
               && gridView.currentIndex >= 0

    function reorderTo(target) {
        if (!shortcuts._canReorder) return false
        if (target < 0 || target >= gridView.count
                || target === gridView.currentIndex) return false
        gridView.groupedModel.moveRow(gridView.currentIndex, target)
        gridView.currentIndex = target
        return true
    }

    Shortcut {
        sequence: "Ctrl+Shift+Right"
        enabled: shortcuts._canReorder && gridView.currentIndex < gridView.count - 1
        onActivated: shortcuts.reorderTo(gridView.currentIndex + 1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Left"
        enabled: shortcuts._canReorder && gridView.currentIndex > 0
        onActivated: shortcuts.reorderTo(gridView.currentIndex - 1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Down"
        enabled: shortcuts._canReorder
                 && gridView.currentIndex + gridView.effectiveColumns < gridView.count
        onActivated: shortcuts.reorderTo(gridView.currentIndex + gridView.effectiveColumns)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Up"
        enabled: shortcuts._canReorder
                 && gridView.currentIndex - gridView.effectiveColumns >= 0
        onActivated: shortcuts.reorderTo(gridView.currentIndex - gridView.effectiveColumns)
    }

    // --- Multi-select (Favorites only) ---

    Shortcut {
        sequence: StandardKey.SelectAll
        enabled: gridView.multiSelectActive && gridView.activeFocus
                 && gridView.count > 0
        onActivated: gridView.selection.selectAllVisible()
    }
    // Delete removes the selected favorites, gated to the favorites view — the
    // All / category views have nothing to remove (apps are listed, not owned),
    // and silently doing nothing there reads as broken, so it stays unbound.
    Shortcut {
        sequence: "Delete"
        enabled: gridView.favoritesActive && gridView.multiSelectActive
                 && gridView.activeFocus && gridView.selection.selectionCount > 0
        onActivated: gridView.removeSelectedFromFavorites()
    }
    // Ctrl+D toggles the favourite state of the highlighted app, or the whole
    // selection — browser-style bookmark, in any view (#193). Gated on grid
    // focus so it never fires while typing in the search field; needs either a
    // selection or a highlighted row (the selection's virtualIndex covers recents + grid).
    Shortcut {
        sequence: "Ctrl+D"
        enabled: gridView.activeFocus
                 && (gridView.selection.selectionCount > 0 || gridView.selection.virtualIndex >= 0)
        onActivated: gridView.toggleFavoritesForSelectionOrCurrent()
    }
}
