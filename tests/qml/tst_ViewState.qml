/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for ViewState.qml — the selected tab and applied search, and
    the apps model filter that follows from them: one model call per change,
    the selection kept through a search, and the category filtering only
    the flat sorts.
*/

import QtQuick
import QtTest

TestCase {
    name: "ViewState"

    // Fake AppFilterModel: the one call the view state makes.
    Component {
        id: fakeModelComponent
        QtObject {
            property string filterCategory: ""
            property bool showFavoritesOnly: false
            property string searchText: ""
            property int stateCalls: 0
            function setSearchState(text, category, favoritesOnly) {
                searchText = text
                filterCategory = category
                showFavoritesOnly = favoritesOnly
                stateCalls++
            }
        }
    }

    function build(props) {
        var model = fakeModelComponent.createObject(null)
        var c = Qt.createComponent("../../package/contents/ui/controllers/ViewState.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        var p = props || {}
        p.appsModel = model
        var state = c.createObject(null, p)
        model.stateCalls = 0
        return { state: state, model: model }
    }

    // --- selection ---

    function test_categoryFiltersFlatSorts() {
        var f = build()
        f.state.selectCategory("Development")
        compare(f.model.filterCategory, "Development")
        compare(f.model.showFavoritesOnly, false)
        compare(f.state.category, "Development")
    }

    function test_categoryDoesNotFilterSectionsOrFolders() {
        var f = build({ categoryFilters: false })
        f.state.selectCategory("Development")
        compare(f.state.category, "Development")
        compare(f.model.filterCategory, "")
    }

    function test_favoritesClearTheCategory() {
        var f = build()
        f.state.selectCategory("Development")
        f.state.selectFavorites(true)
        compare(f.state.favorites, true)
        compare(f.state.category, "")
        compare(f.model.showFavoritesOnly, true)
        compare(f.model.filterCategory, "")
    }

    function test_categoryLeavesFavorites() {
        var f = build()
        f.state.selectFavorites(true)
        f.state.selectCategory("Games")
        compare(f.state.favorites, false)
        compare(f.model.showFavoritesOnly, false)
        compare(f.model.filterCategory, "Games")
    }

    function test_sortChangeRefilters() {
        var f = build()
        f.state.selectCategory("Development")
        f.state.categoryFilters = false
        compare(f.model.filterCategory, "")
        f.state.categoryFilters = true
        compare(f.model.filterCategory, "Development")
    }

    // --- search ---

    function test_searchAllShowsEveryAppAndKeepsTheSelection() {
        var f = build()
        f.state.selectCategory("Development")
        f.state.setSearchText("fire")
        compare(f.model.searchText, "fire")
        compare(f.model.filterCategory, "")
        compare(f.model.showFavoritesOnly, false)
        compare(f.state.category, "Development")

        f.state.setSearchText("")
        compare(f.model.filterCategory, "Development")
        compare(f.model.searchText, "")
    }

    function test_searchAllKeepsTheFavoritesTab() {
        var f = build()
        f.state.selectFavorites(true)
        f.state.setSearchText("fire")
        compare(f.model.showFavoritesOnly, false)
        compare(f.state.favorites, true)
        f.state.setSearchText("")
        compare(f.model.showFavoritesOnly, true)
    }

    function test_searchAllOffSearchesWithinTheSelection() {
        var f = build({ searchAll: false })
        f.state.selectCategory("Development")
        f.state.setSearchText("fire")
        compare(f.model.filterCategory, "Development")
        compare(f.model.searchText, "fire")
    }

    // --- prefix mode ---

    function test_prefixModePushesNoSearch() {
        var f = build({ isPrefixMode: true })
        f.state.selectCategory("Development")
        f.state.setSearchText(":echo hi")
        compare(f.model.searchText, "")
        compare(f.model.filterCategory, "Development")
    }

    function test_prefixToNormalSearchRelaxesThenRestores() {
        var f = build({ isPrefixMode: true })
        f.state.selectCategory("Development")
        f.state.setSearchText("?help")
        compare(f.model.filterCategory, "Development")

        f.state.isPrefixMode = false
        f.state.setSearchText("fire")
        compare(f.model.filterCategory, "")
        compare(f.model.searchText, "fire")

        f.state.setSearchText("")
        compare(f.model.filterCategory, "Development")
    }

    // --- reset ---

    function test_resetGoesToTheStartTab() {
        var f = build()
        f.state.selectCategory("Development")
        f.state.setSearchText("fire")
        f.state.reset(true)
        compare(f.state.favorites, true)
        compare(f.state.category, "")
        compare(f.model.searchText, "")
        compare(f.model.showFavoritesOnly, true)
    }

    // --- one model call per change ---

    function test_eachChangeIsOneModelCall() {
        var f = build()
        f.state.selectFavorites(true)
        compare(f.model.stateCalls, 1)
        f.state.setSearchText("fire")
        compare(f.model.stateCalls, 2)
        f.state.setSearchText("")
        compare(f.model.stateCalls, 3)
        f.state.selectCategory("Games")
        compare(f.model.stateCalls, 4)
    }

    function test_handlesNullModel() {
        var c = Qt.createComponent("../../package/contents/ui/controllers/ViewState.qml")
        var state = c.createObject(null, {})
        state.selectCategory("Development")
        state.setSearchText("fire")
        compare(state.category, "Development")
        compare(state.searching, true)
    }
}
