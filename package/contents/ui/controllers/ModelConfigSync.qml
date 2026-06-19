/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pushes the persisted *settings* (sort, categories, recents cap, search
    toggles) into the AppFilterModel on open and on every reset.

    The per-user launch state — hidden apps, recents, known apps, launch counts —
    is NOT bridged here anymore: it lives in the shared LaunchStateStore
    (appgridrc) and AppGridController syncs it into the model directly in C++, so
    every variant and the daemon share one list. See src/launchstatestore.h.

    `cfg` is the ConfigCache read surface. Kept injected so the panel doesn't
    reach globals and this tests with plain stubs.
*/

import QtQuick

QtObject {
    id: root

    property var appsModel: null
    property var cfg: null // read surface (ConfigCache)

    // Push config -> model. Favorites are loaded separately from
    // KAStatsFavoritesModel after migration (see FavoritesManager.qml); the
    // launch state comes from the controller's LaunchStateStore, not here.
    function sync() {
        if (!appsModel || !cfg)
            return
        appsModel.maxRecentApps = cfg.gridColumns
        appsModel.sortMode = cfg.sortMode
        appsModel.useSystemCategories = cfg.useSystemCategories
        appsModel.sortFavoritesAlphabetically = cfg.sortFavoritesAlphabetically
        appsModel.searchShowsHidden = cfg.searchShowsHidden
        // First run on a machine with no stored known-apps set: treat every app
        // present now as known so the new-app badge only fires for later additions.
        if (appsModel.knownApps.length === 0)
            appsModel.markAllKnown()
    }

    // Keep the recents cap in step with the column count as it changes.
    readonly property int columns: cfg ? cfg.gridColumns : 0
    onColumnsChanged: if (appsModel) appsModel.maxRecentApps = columns
}
