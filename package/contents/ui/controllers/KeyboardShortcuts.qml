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
        KeyboardShortcuts { grid: gridView }
*/

import QtQuick

Item {
    id: shortcuts

    // The owning AppGridView. The reorder shortcuts move the highlighted entry
    // in its grouped favourites model (the stored order, folders included);
    // we read currentIndex, count, effectiveColumns, model, groupedModel,
    // groupEditable and favoritesActive.
    required property GridView grid

    required property bool sortFavoritesAlphabetically

    // --- Favorites reorder (Ctrl+Shift+Arrow) ---

    // Reactive so the Shortcut `enabled` bindings below re-evaluate when any
    // dependency changes — an imperative function call wouldn't track these
    // inside a binding.
    readonly property bool _canReorder: grid.favoritesActive
               && grid.groupEditable
               && !!grid.groupedModel
               && grid.model === grid.groupedModel
               && !sortFavoritesAlphabetically
               && grid.currentIndex >= 0

    function reorderTo(target) {
        if (!shortcuts._canReorder) return false
        if (target < 0 || target >= grid.count
                || target === grid.currentIndex) return false
        grid.groupedModel.moveRow(grid.currentIndex, target)
        grid.currentIndex = target
        return true
    }

    Shortcut {
        sequence: "Ctrl+Shift+Right"
        enabled: shortcuts._canReorder && grid.currentIndex < grid.count - 1
        onActivated: shortcuts.reorderTo(grid.currentIndex + 1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Left"
        enabled: shortcuts._canReorder && grid.currentIndex > 0
        onActivated: shortcuts.reorderTo(grid.currentIndex - 1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Down"
        enabled: shortcuts._canReorder
                 && grid.currentIndex + grid.effectiveColumns < grid.count
        onActivated: shortcuts.reorderTo(grid.currentIndex + grid.effectiveColumns)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Up"
        enabled: shortcuts._canReorder
                 && grid.currentIndex - grid.effectiveColumns >= 0
        onActivated: shortcuts.reorderTo(grid.currentIndex - grid.effectiveColumns)
    }

    // --- Multi-select (Favorites only) ---

    Shortcut {
        sequence: StandardKey.SelectAll
        enabled: grid.multiSelectActive && grid.activeFocus
                 && grid.count > 0
        onActivated: grid.selection.selectAllVisible()
    }
    // Delete removes the selected favorites, gated to the favorites view — the
    // All / category views have nothing to remove (apps are listed, not owned),
    // and silently doing nothing there reads as broken, so it stays unbound.
    Shortcut {
        sequence: "Delete"
        enabled: grid.favoritesActive && grid.multiSelectActive
                 && grid.activeFocus && grid.selection.selectionCount > 0
        onActivated: grid.removeSelectedFromFavorites()
    }
    // Ctrl+D toggles the favourite state of the highlighted app, or the whole
    // selection — browser-style bookmark, in any view (#193). Gated on grid
    // focus so it never fires while typing in the search field; needs either a
    // selection or a highlighted row (the selection's virtualIndex covers recents + grid).
    Shortcut {
        sequence: "Ctrl+D"
        enabled: grid.activeFocus
                 && (grid.selection.selectionCount > 0 || grid.selection.virtualIndex >= 0)
        onActivated: grid.toggleFavoritesForSelectionOrCurrent()
    }
}
