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

    // Mnemonic map: uppercase letter → { type: "all"|"favorites"|"category", name: string }
    property var mnemonicMap: ({})

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

    // -- Mnemonic helpers --

    function rebuildMnemonics() {
        var used = {}
        var map = {}
        var items = []

        items.push({ type: "all", name: i18nd("dev.xarbit.appgrid", "All") })
        var cats = categoryList
        for (var i = 0; i < cats.length; i++)
            items.push({ type: "category", name: cats[i] })
        items.push({ type: "favorites", name: i18nd("dev.xarbit.appgrid", "Favorites") })

        for (var i = 0; i < items.length; i++) {
            var name = items[i].name
            for (var j = 0; j < name.length; j++) {
                var ch = name.charAt(j).toUpperCase()
                if (ch >= 'A' && ch <= 'Z' && !used[ch]) {
                    used[ch] = true
                    map[ch] = items[i]
                    break
                }
            }
        }
        mnemonicMap = map
    }

    function mnemonicText(name) {
        for (var letter in mnemonicMap) {
            var entry = mnemonicMap[letter]
            if (entry.name === name) {
                var idx = name.toUpperCase().indexOf(letter)
                if (idx >= 0)
                    return name.substring(0, idx) + "&" + name.substring(idx)
            }
        }
        return name
    }

    function selectByMnemonic(key) {
        var letter = String.fromCharCode(key).toUpperCase()
        var entry = mnemonicMap[letter]
        if (!entry)
            return false

        if (entry.type === "all") {
            selectAll()
            scrollToSelected()
            return true
        }
        if (entry.type === "favorites") {
            categoryBar.favoritesToggled(!categoryBar.favoritesActive)
            return true
        }
        if (entry.type === "category") {
            selectCategory(entry.name)
            scrollToSelected()
            return true
        }
        return false
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
    }

    // -- "All" button (hidden in scrollOnly/ByCategory mode) --
    PlasmaComponents.ToolButton {
        id: allButton
        visible: !categoryBar.isSortByCategory
        text: categoryBar.mnemonicText(i18nd("dev.xarbit.appgrid", "All"))
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
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
    PlasmaComponents.ToolButton {
        id: scrollLeftBtn
        visible: catFlick.contentX > 0
        icon.name: "arrow-left"
        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        onClicked: {
            catFlick.contentX = Math.max(0, catFlick.contentX - catFlick.width * 0.5)
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

        // Scroll wheel support — translate vertical wheel to horizontal scroll
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                catFlick.contentX = Math.max(0, Math.min(
                    catFlick.contentWidth - catFlick.width,
                    catFlick.contentX - delta))
            }
        }

        Behavior on contentX {
            enabled: Kirigami.Units.longDuration > 0
            SmoothedAnimation { velocity: 800 }
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
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    text: categoryBar.mnemonicText(modelData)
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
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
    PlasmaComponents.ToolButton {
        id: scrollRightBtn
        visible: catFlick.contentX + catFlick.width < catFlick.contentWidth - 1
        icon.name: "arrow-right"
        implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        onClicked: {
            catFlick.contentX = Math.min(
                catFlick.contentWidth - catFlick.width,
                catFlick.contentX + catFlick.width * 0.5)
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
