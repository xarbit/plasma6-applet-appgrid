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
        catRepeater.count, tabMinWidth, Kirigami.Units.smallSpacing)

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
    // When true, selecting a category emits the signal but does not filter the model
    property bool scrollOnlyMode: false
    property string scrollOnlySelected: ""

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

    MnemonicResolver {
        id: mnemonicResolver
        names: [allLabel].concat(categoryList).concat([favoritesLabel])
    }

    function mnemonicIndex(name) { return mnemonicResolver.indexFor(name) }
    function mnemonicRichText(name) { return mnemonicResolver.richTextFor(name) }

    // Selectable tabs in visual (left-to-right) order — the single source
    // of truth for what Alt+Left/Right steps through.
    readonly property var orderedTabs: {
        var tabs = []
        if (favoritesFirst) tabs.push(favoritesLabel)
        if (!isSortByCategory) tabs.push(allLabel)
        tabs = tabs.concat(categoryList)
        if (!favoritesFirst) tabs.push(favoritesLabel)
        return tabs
    }

    // Label of the currently selected tab.
    readonly property string currentTab: {
        if (favoritesActive) return favoritesLabel
        var sel = scrollOnlyMode ? scrollOnlySelected
                                 : (appsModel ? appsModel.filterCategory : "")
        return sel === "" ? allLabel : sel
    }

    // Route a tab label to its action — the single dispatch shared by
    // clicks, mnemonics, Alt+arrow nav, and open-on-hover.
    function selectTab(name) {
        if (name === favoritesLabel)
            selectFavorites()
        else if (name === allLabel)
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
        if (name === favoritesLabel)
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
    function resetScroll() { _setContentX(0) }

    function selectAll() {
        if (categoryBar.favoritesActive)
            categoryBar.favoritesToggled(false)
        if (categoryBar.appsModel)
            categoryBar.appsModel.filterCategory = ""
        scrollOnlySelected = ""
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
        if (isSortByCategory) {
            // By Category mode: turn off favorites, never filter, scroll instead
            if (categoryBar.favoritesActive)
                categoryBar.favoritesToggled(false)
            if (categoryBar.appsModel)
                categoryBar.appsModel.filterCategory = ""
            scrollOnlySelected = name
        } else {
            if (categoryBar.favoritesActive)
                categoryBar.favoritesToggled(false)
            if (categoryBar.appsModel)
                categoryBar.appsModel.filterCategory = name
        }
        categorySelected(name)
    }

    // -- Open-on-hover (#176) --
    // When enabled, dwelling on a tab for hoverActivationDelay selects it
    // without a click. HoverActivation owns the armed-tab state (and the
    // enter-before-leave race); this side just drives the dwell timer.
    property bool openOnHover: false
    readonly property int hoverActivationDelay: 5
    // Cadence for repeated arrow paging on hover; floored at 150ms so it
    // still pages when animations are off. First page fires immediately.
    readonly property int hoverScrollInterval: Math.max(Kirigami.Units.shortDuration * 3, 150)
    // One window governs the whole wheel interaction: hover-select stays
    // suppressed and the highlight stays cleared until this long after the
    // last wheel event, then the scroll counts as stopped and the tab under
    // the cursor is selected once. Must exceed the gap between wheel notches
    // so a multi-notch scroll doesn't settle (and re-select) mid-way.
    readonly property int wheelGrace: Math.max(Kirigami.Units.longDuration, 300)
    // True while a wheel scroll is in progress: drops the tab highlight until
    // the scroll settles and the tab under the cursor is reselected. Purely
    // visual — the grid filter is left untouched so it doesn't flash.
    property bool wheelScrolling: false

    HoverActivation {
        id: hoverActivation
        enabled: categoryBar.openOnHover
        wheelGraceMs: categoryBar.wheelGrace
    }

    // Tracks the pointer crossing the bar's outer bounds, to guard against a
    // cursor merely passing through activating a tab on the way past.
    HoverHandler {
        id: barHover
        onHoveredChanged: categoryBar.hoverBar(hovered)
    }

    Timer {
        id: hoverActivateTimer
        interval: categoryBar.hoverActivationDelay
        onTriggered: if (hoverActivation.pending !== "")
            categoryBar.selectTab(hoverActivation.pending)
    }

    // Fires once a suppression window (wheel scroll or bar entry) elapses with
    // the cursor stationary, so hovered never changes and nothing re-arms —
    // activate whatever tab now sits under the pointer.
    Timer {
        id: wheelSettleTimer
        interval: categoryBar.wheelGrace
        onTriggered: {
            // Restore the highlight first, then reselect the tab now under
            // the cursor (if any) so it ends up the single highlighted one.
            categoryBar.wheelScrolling = false
            if (!categoryBar.openOnHover)
                return
            const name = categoryBar.hoveredTab()
            if (name !== "")
                categoryBar.selectTab(name)
        }
    }

    function hoverEnter(name) {
        if (hoverActivation.enter(name))
            hoverActivateTimer.restart()
    }

    function hoverLeave(name) {
        if (hoverActivation.leave(name))
            hoverActivateTimer.stop()
    }

    // A wheel scroll moves categories under a stationary cursor; suppress
    // hover-select for the grace window so the tab sliding under the pointer
    // isn't auto-selected, drop any dwell in flight, and arm the settle timer
    // so the final tab under the cursor activates once scrolling stops.
    function hoverWheel() {
        hoverActivation.suppress()
        hoverActivateTimer.stop()
        if (!categoryBar.openOnHover)
            return
        categoryBar.wheelScrolling = true
        wheelSettleTimer.restart()
    }

    // Entering the bar from outside: guard against the cursor merely crossing
    // it. Suppress the instant dwell and arm the settle window so a tab fires
    // only if the pointer lingers; a quick pass-through leaves before it does.
    // Leaving the bar cancels everything in flight.
    function hoverBar(inside) {
        if (!categoryBar.openOnHover)
            return
        if (inside) {
            hoverActivation.suppress()
            wheelSettleTimer.restart()
        } else {
            hoverActivation.clear()
            hoverActivateTimer.stop()
            wheelSettleTimer.stop()
        }
    }

    // The selectable tab currently under the cursor, or "" if none.
    function hoveredTab() {
        if (favButtonLeft.visible && favButtonLeft.hovered)
            return favoritesLabel
        if (favButtonRight.visible && favButtonRight.hovered)
            return favoritesLabel
        if (allButton.visible && allButton.hovered)
            return allLabel
        for (var i = 0; i < catRepeater.count; i++) {
            var it = catRepeater.itemAt(i)
            if (it && it.hovered && i < categoryList.length)
                return categoryList[i]
        }
        return ""
    }

    // Effective viewport width for rightward-scroll math — see
    // CategoryScroll.viewportAfterRightScroll for the why.
    function _viewportWidthAfterRightScroll() {
        return CategoryScroll.viewportAfterRightScroll(catFlick.width, catFlick.contentX, scrollArrowWidth)
    }

    // Live delegate rects in visual order, for the page-target math (null for
    // a not-yet-realised delegate; CategoryScroll skips those).
    function _itemRects() {
        var rects = []
        for (var i = 0; i < catRepeater.count; i++) {
            var it = catRepeater.itemAt(i)
            rects.push(it ? { x: it.x, width: it.width } : null)
        }
        return rects
    }

    // Single landing-point for wheel, arrow clicks, alt+arrow, reset.
    // CategoryScroll.clampContentX arms _anchoredRight when the target reaches
    // maxX so contentX stays glued to the right edge as the left arrow expands
    // afterwards (shrinking the viewport, growing maxX). Always lands in-frame
    // (Behavior suppressed) so categories track every input source snappily.
    function _setContentX(target) {
        const r = CategoryScroll.clampContentX(target, catFlick.contentWidth, catFlick.width)
        catFlick._anchoredRight = r.anchoredRight
        catFlick._suppressContentXAnim = true
        catFlick.contentX = r.contentX
        catFlick._suppressContentXAnim = false
    }

    // Page by ~one viewport per click; CategoryScroll picks the boundary-item
    // target (or the matching bound when the page would touch the last/first
    // item, so that arrow can collapse on the same click).
    function pageRight() {
        _setContentX(CategoryScroll.pageRightTarget(_itemRects(), catFlick.contentX,
            _viewportWidthAfterRightScroll(), catFlick.contentWidth, Kirigami.Units.smallSpacing))
    }
    function pageLeft() {
        _setContentX(CategoryScroll.pageLeftTarget(_itemRects(), catFlick.contentX,
            catFlick.width, Kirigami.Units.smallSpacing))
    }

    // Scroll the flickable so the currently selected category button is visible
    function scrollToSelected() {
        Qt.callLater(function() {
            var active = categoryBar.appsModel ? categoryBar.appsModel.filterCategory : ""

            // "All" is selected — scroll to start
            if (active === "") {
                _setContentX(0)
                return
            }

            // Find the matching repeater item, then defer the in/out-of-view
            // decision to CategoryScroll.ensureVisibleTarget.
            for (var i = 0; i < catRepeater.count; i++) {
                var item = catRepeater.itemAt(i)
                if (!item) continue
                var cats = categoryList
                if (i < cats.length && cats[i] === active) {
                    var target = CategoryScroll.ensureVisibleTarget(item.x, item.width,
                        catFlick.contentX, catFlick.width, _viewportWidthAfterRightScroll(),
                        Kirigami.Units.smallSpacing)
                    if (target !== null)
                        _setContentX(target)
                    return
                }
            }
        })
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
        visible: !categoryBar.isSortByCategory
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
        checked: !categoryBar.wheelScrolling
                 && !categoryBar.favoritesActive
                 && (scrollOnlyMode
                     ? scrollOnlySelected === ""
                     : (!categoryBar.appsModel || categoryBar.appsModel.filterCategory === ""))
        onClicked: {
            categoryBar.selectAll()
            catFlick.contentX = 0
        }
        onHoveredChanged: hovered ? categoryBar.hoverEnter(categoryBar.allLabel)
                                  : categoryBar.hoverLeave(categoryBar.allLabel)

        // Always icon-only, so it needs a tooltip like Favorites.
        PlasmaComponents.ToolTip.text: categoryBar.allLabel
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18nd("dev.xarbit.appgrid", "All applications")
        Accessible.role: Accessible.Button
    }

    // The arrow slot animates its width to 0 at the edge so the
    // categories reclaim the space. visible:false would resize the
    // Flickable in a single frame mid-scroll and snap contentX; the
    // animated width gives the layout time to settle smoothly.
    component ScrollArrow: PlasmaComponents.ToolButton {
        id: arrowBtn
        focusPolicy: Qt.NoFocus
        property bool scrollable: false
        // Each arrow supplies its page function; invoked on click and,
        // with open-on-hover on, repeatedly while the arrow is hovered.
        property var pageAction: null
        enabled: scrollable
        opacity: scrollable ? 1 : 0
        implicitWidth: scrollable ? categoryBar.scrollArrowWidth : 0
        Layout.preferredHeight: categoryBar.buttonHeight
        icon.width: categoryBar.buttonIconSize
        icon.height: categoryBar.buttonIconSize
        Layout.rightMargin: scrollable ? 0 : -categoryBar.spacing

        Behavior on implicitWidth {
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on Layout.rightMargin {
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        // Tooltip mirrors the accessible name each instance sets (#171).
        PlasmaComponents.ToolTip.text: Accessible.name
        PlasmaComponents.ToolTip.visible: hovered && scrollable
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        // Open-on-hover: page repeatedly while hovered. triggeredOnStart
        // pages once immediately; the repeat keeps scrolling until the edge
        // is reached (scrollable flips false) or the cursor leaves. Each
        // tick spans the scroll animation so pages chain smoothly.
        Timer {
            running: categoryBar.openOnHover && arrowBtn.hovered
                && arrowBtn.scrollable && arrowBtn.pageAction !== null
            interval: categoryBar.hoverScrollInterval
            repeat: true
            triggeredOnStart: true
            onTriggered: arrowBtn.pageAction()
        }

        Accessible.role: Accessible.Button
    }

    // -- Scroll left arrow --
    ScrollArrow {
        id: scrollLeftBtn
        scrollable: CategoryScroll.arrowVisibility(catFlick.contentX, catFlick.width, catFlick.contentWidth).left
        icon.name: "arrow-left"
        pageAction: () => categoryBar.pageLeft()
        onClicked: categoryBar.pageLeft()
        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories left")
    }

    // -- Scrollable category buttons --
    Flickable {
        id: catFlick
        Layout.fillWidth: true
        implicitHeight: categoryBar.buttonHeight
        contentWidth: catRow.width
        contentHeight: categoryBar.buttonHeight
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        // Arrow slots animate width when they collapse / expand, which
        // changes this Flickable's available width mid-scroll. When
        // _setContentX armed _anchoredRight, glue contentX to the
        // moving maxX in-frame (suppressing the contentX Behavior)
        // so the categories appear stationary while the viewport
        // stretches around them. Otherwise just clamp normally.
        property bool _anchoredRight: false
        property bool _suppressContentXAnim: false
        onWidthChanged: {
            if (_anchoredRight) {
                const maxX = CategoryScroll.maxContentX(contentWidth, width)
                _suppressContentXAnim = true
                contentX = maxX
                _suppressContentXAnim = false
                if (maxX === 0)
                    _anchoredRight = false
            } else {
                returnToBounds()
            }
        }
        onFlickStarted: _anchoredRight = false
        onMovementStarted: _anchoredRight = false

        // Edge-settling guard for #113: once a wheel lands on either edge,
        // swallow follow-up wheels for a short window so rapid scrolling
        // can't re-target the contentX animation and overshoot past max.
        property bool _wheelEdgeSettling: false
        Timer {
            id: wheelEdgeSettlingTimer
            interval: Math.max(Kirigami.Units.shortDuration, 120)
            onTriggered: catFlick._wheelEdgeSettling = false
        }

        Kirigami.WheelHandler {
            target: catFlick
            onWheel: function(wheel) {
                wheel.accepted = true
                categoryBar.hoverWheel()
                if (catFlick._wheelEdgeSettling)
                    return
                const raw = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                const delta = CategoryScroll.clampWheelDelta(raw, catFlick.width,
                    categoryBar.scrollArrowWidth * 4)
                categoryBar._setContentX(catFlick.contentX - delta)
                const maxX = CategoryScroll.maxContentX(catFlick.contentWidth, catFlick.width)
                if (catFlick.contentX === 0 || catFlick.contentX === maxX) {
                    catFlick._wheelEdgeSettling = true
                    wheelEdgeSettlingTimer.restart()
                }
            }
        }

        Behavior on contentX {
            enabled: !catFlick._suppressContentXAnim && Kirigami.Units.longDuration > 0
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            id: catRow
            // Icon-only: fill the viewport (the fillWidth buttons trim their
            // padding to absorb a slightly-wider icon instead of flipping to a
            // scroll), but never below iconRowMinWidth — past that the row
            // overflows so the icons scroll instead of overlapping. Other modes
            // grow with their content and scroll as before.
            width: categoryBar.tabsIconOnly
                   ? Math.max(catFlick.width, categoryBar.iconRowMinWidth)
                   : Math.max(implicitWidth, catFlick.width)
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: catRepeater
                model: categoryBar.categoryList
                delegate: PlasmaComponents.ToolButton {
                    focusPolicy: Qt.NoFocus
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Icon-only: never squish below the icon + padding; past
                    // that the row overflows and scrolls.
                    Layout.minimumWidth: categoryBar.tabsIconOnly ? categoryBar.tabMinWidth : 0
                    required property int index
                    required property string modelData
                    Kirigami.MnemonicData.enabled: false
                    leftPadding: categoryBar.tabHPadding
                    rightPadding: categoryBar.tabHPadding
                    text: ""
                    contentItem: CategoryTabContent {
                        bar: categoryBar
                        label: modelData
                        iconSource: categoryBar.appsModel
                            ? categoryBar.appsModel.categoryIcon(modelData) : ""
                    }
                    checked: !categoryBar.wheelScrolling
                             && !categoryBar.favoritesActive
                             && (scrollOnlyMode
                                 ? scrollOnlySelected === modelData
                                 : (categoryBar.appsModel && categoryBar.appsModel.filterCategory === modelData))
                    onClicked: {
                        categoryBar.selectCategory(modelData)
                        categoryBar.scrollToSelected()
                    }
                    onHoveredChanged: hovered ? categoryBar.hoverEnter(modelData)
                                              : categoryBar.hoverLeave(modelData)

                    // Icon-only hides the label, so surface the category name
                    // on hover; redundant when the label is already shown.
                    PlasmaComponents.ToolTip.text: modelData
                    PlasmaComponents.ToolTip.visible: hovered && categoryBar.tabsIconOnly
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: function(mouse) {
                            if (categoryBar.appsModel && categoryBar.appsModel.useSystemCategories) {
                                catContextMenu.categoryName = modelData
                                catContextMenu.popup()
                            }
                        }
                    }

                    Accessible.name: modelData
                    Accessible.role: Accessible.Button
                }
            }
        }
    }

    // -- Scroll right arrow --
    ScrollArrow {
        id: scrollRightBtn
        scrollable: CategoryScroll.arrowVisibility(catFlick.contentX, catFlick.width, catFlick.contentWidth).right
        icon.name: "arrow-right"
        pageAction: () => categoryBar.pageRight()
        onClicked: categoryBar.pageRight()
        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories right")
    }

    // -- Favorites (right) --
    FavoritesTabButton {
        id: favButtonRight
        visible: !categoryBar.favoritesFirst
        bar: categoryBar
    }

    // -- Category context menu (system categories mode only) --
    PlasmaComponents.Menu {
        id: catContextMenu
        property string categoryName: ""

        PlasmaComponents.MenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Edit \"%1\" in Menu Editor…", catContextMenu.categoryName)
            onClicked: categoryBar.editCategoryInMenu(
                categoryBar.appsModel.categoryMenuPath(catContextMenu.categoryName))
        }
        PlasmaComponents.MenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Open Menu Editor…")
            onClicked: categoryBar.editCategoryInMenu("")
        }
    }
}
