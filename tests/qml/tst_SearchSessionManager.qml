/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for SearchSessionManager.qml — pins the filter
    save/restore swap that runs while the user is searching.
*/

import QtQuick
import QtTest

TestCase {
    name: "SearchSessionManager"

    // Fake AppFilterModel with the three properties the manager reads/writes.
    Component {
        id: fakeModelComponent
        QtObject {
            property string filterCategory: ""
            property bool showFavoritesOnly: false
            property string searchText: ""
        }
    }

    // Fake categoryBar (Item to satisfy the QtObject's `Item` typed input).
    Component {
        id: fakeCategoryBarComponent
        Item {
            property bool favoritesActive: false
        }
    }

    function makeSession(props) {
        var c = Qt.createComponent("SearchSessionManager.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, props || {})
    }

    function build() {
        var model = fakeModelComponent.createObject(null)
        var bar = fakeCategoryBarComponent.createObject(null)
        var s = makeSession({
            appsModel: model,
            categoryBar: bar,
            searchAll: true,
            isPrefixMode: false
        })
        return { session: s, model: model, bar: bar }
    }

    // --- search starts → filters cleared, originals saved ---

    function test_enterSearchClearsFiltersAndStashesOriginals() {
        var f = build()
        f.model.filterCategory = "Development"
        f.bar.favoritesActive = true

        f.session.update("fire")

        compare(f.model.filterCategory, "")
        compare(f.model.showFavoritesOnly, false)
        compare(f.model.searchText, "fire")
        // _savedCategory / _savedFavorites are internal but we can
        // observe them via the restore-on-empty path below.
    }

    function test_exitSearchRestoresOriginalFilters() {
        var f = build()
        f.model.filterCategory = "Development"
        f.bar.favoritesActive = true

        f.session.update("fire")
        f.session.update("")

        compare(f.model.filterCategory, "Development")
        // Restored from the saved categoryBar state, not from the
        // original model state — the Favorites toggle drives both.
        compare(f.model.showFavoritesOnly, true)
        compare(f.bar.favoritesActive, true)
        compare(f.model.searchText, "")
    }

    // --- searchAll off: filters stay put while searching ---

    function test_searchAllOffLeavesFiltersAlone() {
        var f = build()
        f.session.searchAll = false
        f.model.filterCategory = "Development"
        f.bar.favoritesActive = true

        f.session.update("fire")

        compare(f.model.filterCategory, "Development")
        compare(f.bar.favoritesActive, true)
        // searchText still pushed even with searchAll off
        compare(f.model.searchText, "fire")
    }

    // --- prefix mode: no search push, no filter swap ---

    function test_prefixModeSuppressesSearchTextPush() {
        var f = build()
        f.session.isPrefixMode = true

        f.session.update(":echo hi")

        compare(f.model.searchText, "")
    }

    function test_prefixModeDoesNotStashFilters() {
        var f = build()
        f.model.filterCategory = "Development"
        f.session.isPrefixMode = true

        f.session.update(":echo hi")
        f.session.isPrefixMode = false
        f.session.update("")

        // Filter never moved, so the restore path has nothing to put back.
        compare(f.model.filterCategory, "Development")
    }

    // --- idempotent on repeated updates ---

    function test_repeatedSearchDoesNotRestashOriginals() {
        var f = build()
        f.model.filterCategory = "Development"
        f.bar.favoritesActive = false

        f.session.update("fire")
        // Simulate a filter accidentally getting set mid-search — the
        // manager should NOT overwrite its saved state with that value.
        f.model.filterCategory = "Games"
        f.session.update("firef")

        f.session.update("")
        compare(f.model.filterCategory, "Development")
    }

    // --- safe with null inputs ---

    function test_handlesNullModelGracefully() {
        var s = makeSession({ appsModel: null, categoryBar: null,
                              searchAll: true, isPrefixMode: false })
        s.update("anything")
        // Just must not throw.
        verify(true)
    }
}
