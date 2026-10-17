/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Horizontal category filter bar with favorites, "All", and dynamic categories.
    When categories overflow, the bar becomes scrollable with directional arrow buttons.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../js/categoryscroll.js" as CategoryScroll
import "../js/categorybardisplay.js" as Display

RowLayout {
    id: categoryBar

    // Injected from the boundary — opens KMenuEdit at the given menu
    // group path (empty string opens at root).
    required property var editCategoryInMenu

    property var appsModel: null
    // Predicate(sid)->bool injected from the boundary: is the app already a
    // favourite? Used by the Favorites-tab drag-hover to forbid re-adding one.
    property var isFavorite: null
    property bool favoritesActive: false
    property bool favoritesFirst: false

    // Caller-supplied font multiplier applied to All + category buttons
    // so they stay in proportion with the user's icon-size preference.
    // Defaults to 1.0 — the GridPanel boundary overrides with the
    // densityScale derived from cfg.iconSize.
    property real fontScale: 1.0

    // Tab style for the dynamic category tabs: 0=Default (text), 2=Icon+text,
    // 3=Icon (#176). Anchor tabs are always icon-only. Resolved per tab in
    // categorybardisplay.js.
    property int displayMode: 0

    // Icon for the "All" tab — the monochrome freedesktop all-applications glyph.
    readonly property string allIcon: "applications-all-symbolic"

    // True when the non-favorite tabs show only their icon. Such buttons drop
    // to compact padding so the categories fit (and fill) the bar instead of
    // overflowing into a scroll. Favorites is excluded — it is icon-only in
    // more modes but sits outside the scrollable category row.
    readonly property bool tabsIconOnly: !Display.showsText(displayMode, false)
    readonly property real tabHPadding: tabsIconOnly ? Kirigami.Units.smallSpacing
                                                     : Kirigami.Units.largeSpacing

    // Icon-only: a tab never shrinks below its icon plus a little padding, so
    // the glyphs keep breathing room like the Favorites/All anchors instead of
    // squishing. The category row fills the viewport down to the point where
    // every tab is at this minimum, then overflows into a scroll so crowded
    // icons stay reachable. Row geometry lives in CategoryScroll (tested).
    readonly property real tabMinWidth: buttonIconSize + Kirigami.Units.smallSpacing * 2
    readonly property real iconRowMinWidth: CategoryScroll.iconRowMinWidth(
        categoryList.length, tabMinWidth, Kirigami.Units.smallSpacing)

    // -- Shared button geometry (#171) --
    // Every button in the bar — favorites, "All", the scroll arrows and the
    // category tabs — takes its font, height and icon size from these values,
    // so the icon-only buttons track the scaled text buttons instead of
    // standing taller at the Small/Medium presets. All follow fontScale; the
    // 1.1 nudges the bar font just above the body text.
    readonly property real buttonFontPointSize: Kirigami.Theme.defaultFont.pointSize * 1.1 * fontScale
    // Icons follow the size preset in text/icon+text modes, but hold at full
    // smallMedium in icon-only — there the glyph is the only content, so
    // shrinking it at Small/Medium would hurt the legibility icon-only relies on.
    readonly property real buttonIconSize: Math.round(Kirigami.Units.iconSizes.smallMedium
                                                      * (tabsIconOnly ? 1.0 : fontScale))
    // Row height tracks the font, but in icon-only it floors to the (unscaled)
    // icon so the glyph never clips a font-shrunk row.
    readonly property real buttonHeight: Math.max(Math.ceil(_barFontMetrics.height),
                                                  tabsIconOnly ? buttonIconSize : 0)
                                         + Kirigami.Units.smallSpacing * 2

    // The anchor tabs (Favorites, All) are tab markers, so their icon fills the
    // full button height instead of sitting at the smaller buttonIconSize — it
    // reads clearly without making the button or the bar any taller. The anchor
    // buttons drop their vertical padding so the icon can reach this.
    readonly property real anchorIconSize: buttonHeight

    FontMetrics {
        id: _barFontMetrics
        font.pointSize: categoryBar.buttonFontPointSize
    }

    // Reactive category list — updated when model categories change
    property var categoryList: []

    signal favoritesToggled(bool active)
    signal categorySelected(string name)

    // Set when sort mode is By Category
    property bool isSortByCategory: false
    // The selected tab, bound by the host from its view state: the bar only shows
    // and navigates it, and asks for a change through favoritesToggled /
    // categorySelected. The host decides what selecting a category does (filter
    // the grid, scroll to a section, or root the folder tree), so the tab
    // highlight, Alt+arrow stepping and scroll-into-view behave identically
    // regardless of sort. (#201)
    property string selectedCategory: ""

    property bool hideEmptyCategories: true

    // Rebuilds the category list from the model, optionally hiding empty categories
    function refreshCategories() {
        var cats;
        if (hideEmptyCategories && categoryBar.appsModel)
            cats = categoryBar.appsModel.nonEmptyCategories().sort()
        else
            cats = categoryBar.appsModel ? categoryBar.appsModel.categories() : []

        categoryList = cats
    }

    // -- Mnemonic system --
    // Custom mnemonic handling — Plasma's built-in MnemonicData is unreliable
    // with many dynamic buttons. We assign first unique letter per category
    // and handle Alt+letter ourselves.

    property bool altHeld: false
    readonly property string allLabel: i18nd("dev.xarbit.appgrid", "All")
    readonly property string favoritesLabel: i18nd("dev.xarbit.appgrid", "Favorites")

    // Tabs are named by id: a category's id is its name, the two anchors use
    // ids no category name can take. Matching on the shown label instead sent
    // a category named like an anchor (a menu folder "Favorites", a category
    // whose translation reads "All") to the anchor.
    readonly property string allTab: "\u0001all"
    readonly property string favoritesTab: "\u0001favorites"
    function tabLabel(id) {
        return id === allTab ? allLabel : id === favoritesTab ? favoritesLabel : id
    }

    MnemonicResolver {
        id: mnemonicResolver
        names: [allTab].concat(categoryList).concat([favoritesTab])
        labelOf: categoryBar.tabLabel
    }

    function mnemonicIndex(name) { return mnemonicResolver.indexFor(name) }
    function mnemonicRichText(name) { return mnemonicResolver.richTextFor(name) }

    // Selectable tab ids in visual (left-to-right) order — the single source
    // of truth for what Alt+Left/Right steps through.
    readonly property var orderedTabs: {
        var tabs = []
        if (favoritesFirst) tabs.push(favoritesTab)
        // All is a real tab in every view now — including the By Category grid,
        // where it scrolls back to the top / clears the filter (#201).
        tabs.push(allTab)
        tabs = tabs.concat(categoryList)
        if (!favoritesFirst) tabs.push(favoritesTab)
        return tabs
    }

    // Id of the currently selected tab.
    readonly property string currentTab: {
        if (favoritesActive) return favoritesTab
        var sel = selectedCategory
        return sel === "" ? allTab : sel
    }

    // Route a tab id to its action — the single dispatch shared by
    // clicks, mnemonics, Alt+arrow nav, and open-on-hover.
    function selectTab(name) {
        if (name === favoritesTab)
            selectFavorites()
        else if (name === allTab)
            selectAll()
        else
            selectCategory(name)
    }

    // selectTab plus scroll-into-view — for mnemonics, Alt+arrow
    // navigation, and programmatic selection. Hover deliberately omits the
    // scroll so the dwelled-on tab doesn't slide out from under the cursor.
    function selectByName(name) {
        selectTab(name)
        scrollToSelected()
    }

    function selectByMnemonic(key) {
        var name = mnemonicResolver.nameForKey(key)
        if (!name) return false
        // Favorites and every other tab select; nothing toggles (#169).
        if (name === favoritesTab)
            selectFavorites()
        else
            selectByName(name)
        return true
    }

    // Step the selection one tab left (-1) or right (+1).
    function selectAdjacentCategory(step) {
        var tabs = orderedTabs
        var cur = tabs.indexOf(currentTab)
        var next = cur < 0 ? (step > 0 ? 0 : tabs.length - 1) : cur + step
        if (next >= 0 && next < tabs.length && next !== cur)
            selectByName(tabs[next])
    }

    // -- Category action helpers --

    function closeCategoryMenu() { catContextMenu.close() }
    function resetScroll() { tabStrip.setContentX(0) }

    function selectAll() {
        categorySelected("")
    }

    // Selecting favorites is one-way: it activates the favorites tab and
    // never toggles back to All. Leaving favorites goes through selectAll()
    // (the All button / Alt+A), which keeps click and keyboard consistent
    // and stops the favorites button cycling All↔Favorites (#169).
    function selectFavorites() {
        favoritesToggled(true)
    }

    function selectCategory(name) {
        categorySelected(name)
    }

    // -- Open-on-hover (#176) --
    property bool openOnHover: false
    // The tabs and arrows report hover to it; it selects a dwelled-on tab.
    readonly property alias hover: hoverSelect
    CategoryHoverSelect {
        id: hoverSelect
        enabled: categoryBar.openOnHover
        tabUnderPointer: categoryBar.hoveredTab
        onSelectRequested: tabId => categoryBar.selectTab(tabId)
    }

    // Tracks the pointer crossing the bar's outer bounds, to guard against a
    // cursor merely passing through activating a tab on the way past.
    HoverHandler {
        onHoveredChanged: hoverSelect.crossBar(hovered)
    }

    // The selectable tab currently under the cursor, or "" if none.
    function hoveredTab() {
        if (favButtonLeft.visible && favButtonLeft.hovered)
            return favoritesTab
        if (favButtonRight.visible && favButtonRight.hovered)
            return favoritesTab
        if (allButton.visible && allButton.hovered)
            return allTab
        return tabStrip.hoveredCategory()
    }

    // Scroll the selected category's tab into view.
    function scrollToSelected() {
        Qt.callLater(() => tabStrip.scrollToTab(categoryBar.selectedCategory))
    }

    Component.onCompleted: refreshCategories()
    onAppsModelChanged: refreshCategories()
    Connections {
        target: categoryBar.appsModel
        function onCategoriesChanged() { categoryBar.refreshCategories() }
        function onHiddenAppsChanged() { categoryBar.refreshCategories() }
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    readonly property real scrollArrowWidth: categoryBar.buttonIconSize + Kirigami.Units.smallSpacing * 2

    // -- Favorites (left) --
    FavoritesTabButton {
        id: favButtonLeft
        visible: categoryBar.favoritesFirst
        bar: categoryBar
    }

    // -- "All" button (hidden in scrollOnly/ByCategory mode) --
    PlasmaComponents.ToolButton {
        id: allButton
        // Shown in every view now, including By Category (#201).
        visible: true
        // Keep focus on the search field so Alt+arrow nav survives a click (#174).
        focusPolicy: Qt.NoFocus
        Kirigami.MnemonicData.enabled: false
        text: ""
        Layout.preferredHeight: categoryBar.buttonHeight
        // Anchor tab like Favorites: always icon-only, the glyph fills the
        // button height (zero vertical padding); horizontal padding stays at
        // the ToolButton default so both anchors match.
        topPadding: 0
        bottomPadding: 0
        contentItem: CategoryTabContent {
            bar: categoryBar
            label: categoryBar.allLabel
            iconSource: categoryBar.allIcon
            isAnchor: true
            mnemonic: false
            iconSize: categoryBar.anchorIconSize
        }
        checked: !categoryBar.hover.wheelScrolling
                 && !categoryBar.favoritesActive
                 && categoryBar.selectedCategory === ""
        onClicked: {
            categoryBar.selectAll()
            tabStrip.scrollToStart()
        }
        onHoveredChanged: hovered ? categoryBar.hover.enter(categoryBar.allTab)
                                  : categoryBar.hover.leave(categoryBar.allTab)

        // Always icon-only, so it needs a tooltip like Favorites.
        PlasmaComponents.ToolTip.text: categoryBar.allLabel
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18nd("dev.xarbit.appgrid", "All applications")
        Accessible.role: Accessible.Button
    }

    // -- Scrollable category tabs --
    CategoryTabStrip {
        id: tabStrip
        bar: categoryBar
        Layout.fillWidth: true
        onContextMenuRequested: name => {
            catContextMenu.categoryName = name
            catContextMenu.popup()
        }
    }

    // -- Favorites (right) --
    FavoritesTabButton {
        id: favButtonRight
        visible: !categoryBar.favoritesFirst
        bar: categoryBar
    }

    // -- Category context menu (system categories mode only) --
    AppGridMenu {
        id: catContextMenu
        property string categoryName: ""

        AppGridMenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Edit \"%1\" in Menu Editor…", catContextMenu.categoryName)
            onClicked: categoryBar.editCategoryInMenu(
                categoryBar.appsModel.categoryMenuPath(catContextMenu.categoryName))
        }
        AppGridMenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Open Menu Editor…")
            onClicked: categoryBar.editCategoryInMenu("")
        }
    }
}
