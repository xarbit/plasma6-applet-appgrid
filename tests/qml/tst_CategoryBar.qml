/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for CategoryBar.qml's tab routing: tabs are named by id, so a
    category whose name reads like an anchor tab ("All", "Favorites") is still
    its own category, for clicks, Alt+arrow stepping and mnemonics alike.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/widgets"

TestCase {
    id: testCase
    name: "CategoryBar"
    width: 800
    height: 100
    when: windowShown

    QtObject {
        id: appsStub
        property bool useSystemCategories: false
        signal categoriesChanged()
        signal hiddenAppsChanged()
        function categories() { return ["All", "Favorites", "Games"] }
        function nonEmptyCategories() { return categories() }
        function categoryIcon(name) { return "" }
        function categoryMenuPath(name) { return "" }
    }

    Component {
        id: barComponent
        CategoryBar {
            width: 800
            appsModel: appsStub
            hideEmptyCategories: false
            editCategoryInMenu: path => {}
        }
    }

    SignalSpy { id: categorySpy; signalName: "categorySelected" }
    SignalSpy { id: favoritesSpy; signalName: "favoritesToggled" }

    function make() {
        var bar = createTemporaryObject(barComponent, testCase)
        verify(bar)
        bar.refreshCategories()
        categorySpy.target = bar
        favoritesSpy.target = bar
        categorySpy.clear()
        favoritesSpy.clear()
        return bar
    }

    function test_categoriesNamedLikeAnchorsAreCategories() {
        var bar = make()
        compare(bar.orderedTabs.length, 5, "All, three categories, Favorites")
        bar.selectTab("All")
        compare(categorySpy.count, 1)
        compare(categorySpy.signalArguments[0][0], "All", "the category, not the All tab")
        bar.selectTab("Favorites")
        compare(favoritesSpy.count, 0, "the category, not the Favorites tab")
        compare(categorySpy.signalArguments[1][0], "Favorites")

        bar.selectTab(bar.allTab)
        compare(categorySpy.signalArguments[2][0], "", "the All tab clears the category")
        bar.selectTab(bar.favoritesTab)
        compare(favoritesSpy.count, 1)
    }

    function test_steppingVisitsEveryTab() {
        var bar = make()
        bar.selectedCategory = ""
        compare(bar.currentTab, bar.allTab)
        bar.selectAdjacentCategory(1)
        compare(categorySpy.signalArguments[0][0], "All", "steps from the All tab to the category")
        bar.selectedCategory = "All"
        compare(bar.currentTab, "All")
        bar.selectAdjacentCategory(1)
        compare(categorySpy.signalArguments[1][0], "Favorites")
    }

    function test_mnemonicsUseLabelsAndRouteById() {
        var bar = make()
        // The All tab takes A from its label; the category "All" falls back to L.
        verify(bar.selectByMnemonic(Qt.Key_A))
        compare(categorySpy.signalArguments[0][0], "", "Alt+A is the All tab")
        verify(bar.selectByMnemonic(Qt.Key_L))
        compare(categorySpy.signalArguments[1][0], "All", "Alt+L is the category")
        compare(bar.mnemonicRichText("All"), "A<u>l</u>l")
    }

    // The tab strip scrolls a picked tab into view and back to the start.
    function test_stripScrollsWithoutErrors() {
        var bar = make()
        bar.selectedCategory = "Games"
        bar.scrollToSelected()
        wait(50)
        bar.resetScroll()
        compare(bar.hoveredTab(), "", "nothing under the pointer")
    }
}
