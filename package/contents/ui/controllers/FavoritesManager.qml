/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    KAStats-backed favorites lifecycle: loads the favourites model, mirrors the
    live model into AppFilterModel for alpha-sort, and coalesces the burst of
    source signals into one mirror per event-loop turn.

    Pure mirror-id collection lives in favoritesmigration.js so it is
    unit-tested in isolation; this file owns the Plasma-glue around it.
*/

import QtQuick

import "../js/favoritesmigration.js" as FavoritesMigration

Item {
    id: manager

    // --- Inputs ---

    property var appsModel: null

    // The C++ grouped model (issue #18). Fed the live flat favourite list on
    // every KAStats change so it can reconcile its folder layout; left null
    // disables folders (e.g. tests).
    property var favoritesGroupedModel: null

    // KAStats client id for the favorites provider. Production builds it
    // from the plasmoid id; the default keeps tests isolated from the
    // user's real favorites store.
    property string clientInstance: "dev.xarbit.appgrid.favorites.instance-test"

    // Config inputs, injected from the boundary's ConfigCache.
    required property bool sortFavoritesAlphabetically

    // --- Outputs (panel re-exposes these via aliases) ---

    // The shared model's favourite-id role, read from the model itself on load.
    // -1 means "not yet known"; consumers must guard on that before reading row
    // data at the role.
    property int favoriteIdRole: -1
    readonly property var sharedFavoritesModel: sharedFavoritesLoader.item

    // Drives whether the live model gets mirrored into AppFilterModel.
    // Only alpha-sort needs that; drag-reorder reads the shared model
    // directly.
    readonly property bool mirrorRequired: manager.sortFavoritesAlphabetically

    // No layout; pure controller.
    visible: false

    // --- Provider ---
    //
    // SharedFavoritesProvider instantiates AppGrid's own favourites model
    // (src/appgridfavoritesmodel). Kept behind a Loader so a registration
    // failure is logged rather than crashing the rest of the plasmoid.
    Loader {
        id: sharedFavoritesLoader
        active: true
        source: "../models/SharedFavoritesProvider.qml"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("AppGrid: favourites model failed to load — favorites disabled")
                return
            }
            if (status === Loader.Ready && item) {
                item.initForClient(manager.clientInstance)
                // The model publishes its own favourite-id role; no probing.
                manager.favoriteIdRole = item.favoriteIdRole
                if (item.enabled)
                    manager._refreshMirror()
            }
        }
    }

    // --- Mirror ---

    function _refreshMirror() {
        if (favoriteIdRole < 0) return
        _mirrorFavorites()
        _pushGrouped()
    }

    function _mirrorFavorites() {
        if (!appsModel || !sharedFavoritesModel) return
        if (favoriteIdRole < 0) return
        appsModel.favoriteApps = FavoritesMigration.collectMirrorIds(
            sharedFavoritesModel, favoriteIdRole)
    }

    // Push the live, ordered favourite ids into the grouped model so it can
    // reconcile its folder layout against the real favourites (issue #18). Runs
    // regardless of alpha-sort — folders are independent of the mirror.
    function _pushGrouped() {
        if (!favoritesGroupedModel || !sharedFavoritesModel) return
        if (favoriteIdRole < 0) return
        favoritesGroupedModel.setFlatFavorites(
            FavoritesMigration.collectMirrorIds(sharedFavoritesModel, favoriteIdRole))
    }

    // --- Watchers ---

    Connections {
        target: sharedFavoritesLoader.item
        ignoreUnknownSignals: true
        function onEnabledChanged() {
            if (sharedFavoritesLoader.item && sharedFavoritesLoader.item.enabled)
                manager._refreshMirror()
        }
    }

    // Coalesce the burst of model signals (insert/remove/move/reset/
    // layoutChanged/dataChanged often fire back-to-back) into one mirror per
    // event-loop turn. The mirror only runs in alpha-sort mode; drag-reorder
    // reads the shared model directly.
    Timer {
        id: mirrorCoalesce
        interval: 0
        repeat: false
        onTriggered: {
            if (manager.mirrorRequired)
                manager._mirrorFavorites()
            manager._pushGrouped()
        }
    }

    // Catch up the proxy when the user enables alpha-sort mid-session.
    onMirrorRequiredChanged: {
        if (mirrorRequired) mirrorCoalesce.restart()
    }

    Connections {
        target: manager.sharedFavoritesModel
        ignoreUnknownSignals: true
        function _scheduleMirror() {
            // Migration finalisation still needs to happen even when not
            // mirroring (so the ported flag flips once KAStats has data).
            mirrorCoalesce.restart()
        }
        function onRowsInserted() { _scheduleMirror() }
        function onRowsRemoved() { _scheduleMirror() }
        function onRowsMoved() { _scheduleMirror() }
        function onModelReset() { _scheduleMirror() }
        function onLayoutChanged() { _scheduleMirror() }
        function onDataChanged() { _scheduleMirror() }
    }
}
