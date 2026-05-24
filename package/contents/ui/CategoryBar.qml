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
    property bool devExtraCategories: false
    property bool favoritesFirst: false

    // Reactive category list — updated when model categories change
    property var categoryList: []

    // Dev test categories injected when DEV_EXTRA_CATEGORIES is enabled
    readonly property var testCategories: [
        "Education", "Science", "Games", "Accessibility",
        "Photography", "Video", "Audio", "Network",
        "Finance", "News", "Weather", "Navigation"
    ]

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

        if (categoryBar.devExtraCategories)
            cats = cats.concat(categoryBar.testCategories)

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
    function resetScroll() { catFlick.contentX = 0 }

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

    // Scroll the flickable so the currently selected category button is visible
    function scrollToSelected() {
        Qt.callLater(function() {
            var active = categoryBar.appsModel ? categoryBar.appsModel.filterCategory : ""

            // "All" is selected — scroll to start
            if (active === "") {
                catFlick.contentX = 0
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
                        catFlick.contentX = Math.max(0, itemLeft - Kirigami.Units.smallSpacing)
                    else if (itemRight > viewRight)
                        catFlick.contentX = Math.min(
                            catFlick.contentWidth - catFlick.width,
                            itemRight - catFlick.width + Kirigami.Units.smallSpacing)
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

    // -- Scroll left slot --
    // Reserves a fixed-width slot regardless of state so the bar never
    // reflows when the arrow appears or disappears. Holds either the
    // separator (idle) or the arrow button (scrollable).
    Item {
        id: scrollLeftSlot
        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        implicitHeight: scrollLeftBtn.implicitHeight

        Kirigami.Separator {
            anchors.centerIn: parent
            width: 1
            height: parent.height * 0.5
            visible: !scrollLeftBtn.visible
        }

        PlasmaComponents.ToolButton {
            id: scrollLeftBtn
            anchors.fill: parent
            visible: catFlick.contentX > 0
            icon.name: "arrow-left"
            onClicked: catFlick.contentX = Math.max(0, catFlick.contentX - catFlick.width)

            Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories left")
            Accessible.role: Accessible.Button
        }
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
                const maxX = Math.max(0, catFlick.contentWidth - catFlick.width)
                const target = Math.max(0, Math.min(maxX, catFlick.contentX - delta))
                catFlick.contentX = target
                if (target === 0 || target === maxX) {
                    catFlick._wheelEdgeSettling = true
                    wheelEdgeSettlingTimer.restart()
                }
            }
        }

        Behavior on contentX {
            enabled: Kirigami.Units.longDuration > 0
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

    // -- Scroll right arrow --
    // Fade with opacity rather than collapse with visible: false — visible
    // toggling removes the button from the parent RowLayout mid-scroll,
    // growing catFlick at the moment the user lands on the right edge and
    // visibly overshooting the new max. Left arrow can use visible:false
    // safely because the layout shift there happens at idle (contentX = 0).
    PlasmaComponents.ToolButton {
        id: scrollRightBtn
        enabled: catFlick.contentX + catFlick.width < catFlick.contentWidth - 1
        opacity: enabled ? 1 : 0
        icon.name: "arrow-right"
        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        onClicked: catFlick.contentX = Math.min(
            catFlick.contentWidth - catFlick.width,
            catFlick.contentX + catFlick.width)

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
