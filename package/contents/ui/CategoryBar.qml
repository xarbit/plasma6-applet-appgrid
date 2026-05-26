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
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasmoid

RowLayout {
    id: categoryBar

    Kicker.ProcessRunner { id: processRunner }

    property var appsModel: null
    property bool favoritesActive: false
    property bool favoritesFirst: false

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

    // Trigger from outside; kept for API compatibility with previous code.
    function rebuildMnemonics() { /* MnemonicResolver recomputes via binding */ }

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

    // Select a tab by label — single dispatch point for mnemonics,
    // Alt+arrow navigation, and programmatic selection.
    function selectByName(name) {
        if (name === favoritesLabel)
            favoritesToggled(true)
        else if (name === allLabel)
            selectAll()
        else
            selectCategory(name)
        scrollToSelected()
    }

    function selectByMnemonic(key) {
        var name = mnemonicResolver.nameForKey(key)
        if (!name) return false
        // A mnemonic on Favorites toggles it; every other tab selects.
        if (name === favoritesLabel)
            favoritesToggled(!favoritesActive)
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

    // Effective viewport width for rightward-scroll math. When at
    // contentX = 0 the left arrow slot is currently 0 but will
    // expand right after the scroll, narrowing the viewport — page
    // and alt+arrow targets computed against the raw width would
    // leave the landed item half-clipped after the expand.
    function _viewportWidthAfterRightScroll() {
        return catFlick.width - (catFlick.contentX <= 0 ? scrollArrowWidth : 0)
    }

    // Single landing-point for wheel, arrow clicks, alt+arrow, reset.
    // Arms _anchoredRight when target reaches maxX so contentX stays
    // glued to the right edge as the left arrow expands afterwards
    // (which shrinks the viewport and grows maxX) — without it the
    // right arrow stays visible because contentX falls short of the
    // new bound. Always lands in-frame (Behavior suppressed) so the
    // categories track every input source snappily.
    function _setContentX(target) {
        const maxX = Math.max(0, catFlick.contentWidth - catFlick.width)
        const clamped = Math.max(0, Math.min(maxX, target))
        catFlick._anchoredRight = (clamped === maxX && maxX > 0)
        catFlick._suppressContentXAnim = true
        catFlick.contentX = clamped
        catFlick._suppressContentXAnim = false
    }

    // Page by ~one viewport per click, anchoring the boundary item so
    // it's fully visible (no half-clip). If the next page would
    // touch the last/first item at all, snap to the matching bound
    // so the page lands cleanly and the matching arrow can collapse
    // on the same click — the Flickable re-clamps automatically when
    // the arrow slot resizes.
    function pageRight() {
        const W = _viewportWidthAfterRightScroll()
        const tentativeRight = catFlick.contentX + 2 * W
        var lastFit = -1
        for (var i = 0; i < catRepeater.count; i++) {
            var it = catRepeater.itemAt(i)
            if (!it) continue
            if (it.x + it.width <= tentativeRight + 1) lastFit = i
            else break
        }
        if (lastFit < 0 || lastFit === catRepeater.count - 1) {
            _setContentX(catFlick.contentWidth)
            return
        }
        var fitItem = catRepeater.itemAt(lastFit)
        const target = (fitItem.x + fitItem.width) - W + Kirigami.Units.smallSpacing
        var lastItem = catRepeater.itemAt(catRepeater.count - 1)
        if (lastItem && lastItem.x < target + W + 1) {
            _setContentX(catFlick.contentWidth)
            return
        }
        _setContentX(target)
    }
    function pageLeft() {
        const W = catFlick.width
        const tentativeLeft = catFlick.contentX - W
        var firstFit = -1
        for (var i = 0; i < catRepeater.count; i++) {
            var it = catRepeater.itemAt(i)
            if (!it) continue
            if (it.x >= tentativeLeft - 1) { firstFit = i; break }
        }
        if (firstFit <= 0) {
            _setContentX(0)
            return
        }
        const target = catRepeater.itemAt(firstFit).x - Kirigami.Units.smallSpacing
        var firstItem = catRepeater.itemAt(0)
        if (firstItem && firstItem.x + firstItem.width > target - 1) {
            _setContentX(0)
            return
        }
        _setContentX(target)
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

            // Find the matching repeater item
            for (var i = 0; i < catRepeater.count; i++) {
                var item = catRepeater.itemAt(i)
                if (!item) continue
                var cats = categoryList
                if (i < cats.length && cats[i] === active) {
                    var itemLeft = item.x
                    var itemRight = item.x + item.width
                    var viewLeft = catFlick.contentX
                    var viewRight = catFlick.contentX + catFlick.width

                    if (itemLeft < viewLeft)
                        _setContentX(itemLeft - Kirigami.Units.smallSpacing)
                    else if (itemRight > viewRight)
                        _setContentX(itemRight - _viewportWidthAfterRightScroll()
                                                + Kirigami.Units.smallSpacing, true)
                    return
                }
            }
        })
    }

    Component.onCompleted: { refreshCategories(); rebuildMnemonics() }
    onAppsModelChanged: { refreshCategories(); rebuildMnemonics() }
    Connections {
        target: categoryBar.appsModel
        function onCategoriesChanged() { categoryBar.refreshCategories(); categoryBar.rebuildMnemonics() }
        function onHiddenAppsChanged() { categoryBar.refreshCategories(); categoryBar.rebuildMnemonics() }
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    readonly property int scrollArrowWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2

    // -- Favorites (left) --
    PlasmaComponents.ToolButton {
        id: favButtonLeft
        visible: categoryBar.favoritesFirst
        icon.name: "bookmarks-bookmarked"
        checked: categoryBar.favoritesActive
        onClicked: categoryBar.favoritesToggled(!categoryBar.favoritesActive)

        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Favorites")
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18nd("dev.xarbit.appgrid", "Favorites")
        Accessible.role: Accessible.Button

        FavoritesTabDragHover { target: categoryBar }
    }

    // -- "All" button (hidden in scrollOnly/ByCategory mode) --
    PlasmaComponents.ToolButton {
        id: allButton
        visible: !categoryBar.isSortByCategory
        Kirigami.MnemonicData.enabled: false
        text: ""
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        contentItem: PlasmaComponents.Label {
            text: categoryBar.altHeld
                ? categoryBar.mnemonicRichText(i18nd("dev.xarbit.appgrid", "All"))
                : i18nd("dev.xarbit.appgrid", "All")
            textFormat: categoryBar.altHeld ? Text.RichText : Text.PlainText
            font: parent.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        checked: !categoryBar.favoritesActive
                 && (scrollOnlyMode
                     ? scrollOnlySelected === ""
                     : (!categoryBar.appsModel || categoryBar.appsModel.filterCategory === ""))
        onClicked: {
            categoryBar.selectAll()
            catFlick.contentX = 0
        }

        Accessible.name: i18nd("dev.xarbit.appgrid", "All applications")
        Accessible.role: Accessible.Button
    }

    // -- Scroll left arrow --
    // The slot animates its width to 0 at the edge so the categories
    // reclaim the space. visible:false would resize the Flickable in a
    // single frame mid-scroll and snap contentX; an animated width gives
    // the layout time to settle smoothly. The edge condition is
    // pre-computed from contentX so the slot grows back the frame the
    // user pages off.
    PlasmaComponents.ToolButton {
        id: scrollLeftBtn
        readonly property bool _scrolled: catFlick.contentX > 0
        enabled: _scrolled
        opacity: _scrolled ? 1 : 0
        implicitWidth: _scrolled ? categoryBar.scrollArrowWidth : 0
        icon.name: "arrow-left"
        onClicked: categoryBar.pageLeft()

        Behavior on implicitWidth {
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories left")
        Accessible.role: Accessible.Button
    }

    // -- Scrollable category buttons --
    Flickable {
        id: catFlick
        Layout.fillWidth: true
        implicitHeight: catRow.implicitHeight
        contentWidth: catRow.width
        contentHeight: catRow.implicitHeight
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
                const maxX = Math.max(0, contentWidth - width)
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
                if (catFlick._wheelEdgeSettling)
                    return
                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                categoryBar._setContentX(catFlick.contentX - delta)
                const maxX = Math.max(0, catFlick.contentWidth - catFlick.width)
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
            width: Math.max(implicitWidth, catFlick.width)
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: catRepeater
                model: categoryBar.categoryList
                delegate: PlasmaComponents.ToolButton {
                    Layout.fillWidth: true
                    required property int index
                    required property string modelData
                    Kirigami.MnemonicData.enabled: false
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    text: ""
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    contentItem: PlasmaComponents.Label {
                        text: categoryBar.altHeld
                            ? categoryBar.mnemonicRichText(modelData)
                            : modelData
                        textFormat: categoryBar.altHeld ? Text.RichText : Text.PlainText
                        font: parent.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    checked: !categoryBar.favoritesActive
                             && (scrollOnlyMode
                                 ? scrollOnlySelected === modelData
                                 : (categoryBar.appsModel && categoryBar.appsModel.filterCategory === modelData))
                    onClicked: {
                        categoryBar.selectCategory(modelData)
                        categoryBar.scrollToSelected()
                    }

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

    // -- Scroll right arrow -- same animated slot as the left.
    PlasmaComponents.ToolButton {
        id: scrollRightBtn
        readonly property bool _scrollable: catFlick.contentX + catFlick.width < catFlick.contentWidth - 1
        enabled: _scrollable
        opacity: _scrollable ? 1 : 0
        implicitWidth: _scrollable ? categoryBar.scrollArrowWidth : 0
        icon.name: "arrow-right"
        onClicked: categoryBar.pageRight()

        Behavior on implicitWidth {
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories right")
        Accessible.role: Accessible.Button
    }

    // -- Favorites (right) --
    PlasmaComponents.ToolButton {
        id: favButtonRight
        visible: !categoryBar.favoritesFirst
        icon.name: "bookmarks-bookmarked"
        checked: categoryBar.favoritesActive
        onClicked: categoryBar.favoritesToggled(!categoryBar.favoritesActive)

        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Favorites")
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18nd("dev.xarbit.appgrid", "Favorites")
        Accessible.role: Accessible.Button

        FavoritesTabDragHover { target: categoryBar }
    }

    // -- Category context menu (system categories mode only) --
    PlasmaComponents.Menu {
        id: catContextMenu
        property string categoryName: ""

        PlasmaComponents.MenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Edit \"%1\" in Menu Editor…", catContextMenu.categoryName)
            onClicked: {
                var menuPath = categoryBar.appsModel.categoryMenuPath(catContextMenu.categoryName)
                processRunner.runMenuEditor(menuPath || "")
            }
        }
        PlasmaComponents.MenuItem {
            icon.name: "kmenuedit"
            text: i18nd("dev.xarbit.appgrid", "Open Menu Editor…")
            onClicked: processRunner.runMenuEditor()
        }
    }
}
