/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Read-only drill-down over the kmenuedit menu tree, for the By Category view
    when "group categories into folders" is on (issue #201).

    This is a thin host: the grid itself is an AppGridView bound to the menu tree
    (a grouped model), so the icon delegate, selection, drag-and-drop and the app
    context menu are exactly the regular grid's — no duplication. The menu tree is
    read-only (groupEditable: false), so reorder / drag-to-folder / create-folder
    are off. This view only adds the drill chrome (back + breadcrumb) and routes
    folder activation to enterFolder / goBack instead of the favourites overlay.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../controllers"
import "../widgets"

Item {
    id: root

    // MenuTreeModel: AbstractGroupedModel rows for the current path, plus
    // enterFolder / goBack / canGoBack / currentFolderName.
    property var menuModel: null
    // The panel this view lives in (GridHost), handed to its grid.
    required property GridHost host
    // Drop folders with no app anywhere in their subtree ("hide empty categories").
    property bool hideEmpty: false

    // Right-click on a folder → edit it in the menu editor (menuPath = kmenuedit
    // relPath, trailing slash stripped).
    signal folderContextRequested(string menuPath)

    // Drill selection + the canGoBack mirror, shared with the favourites grid.
    readonly property alias canGoBack: nav.canGoBack
    // The category bar picked @p name: root the tree at its menu folder, or at
    // all categories for All ("").
    function showCategory(name) {
        if (!menuModel)
            return
        const appsModel = host.appsModel
        menuModel.setRootPath(name !== "" && appsModel ? appsModel.categoryMenuPath(name) : "")
    }
    function enterFromSearch() { menuGrid.enterFromSearch() }
    function activateCurrent() { menuGrid.activateCurrent() }
    // Back to the just-opened state: the tree at all categories, and the
    // navigation's memory cleared so the last folder doesn't flash on open.
    function reset() {
        showCategory("")
        nav.reset()
    }

    DrillNavigator {
        id: nav
        model: root.menuModel
        grid: menuGrid
    }

    // Push hideEmpty into the (controller-owned) model; it rebuilds its rows.
    Binding {
        target: root.menuModel
        property: "hideEmpty"
        value: root.hideEmpty
        when: !!root.menuModel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // Back + breadcrumb (read-only: the menu tree isn't editable).
        DrillBar {
            Layout.fillWidth: true
            model: root.menuModel
            editable: false
        }

        AppGridView {
            id: menuGrid
            Layout.fillWidth: true
            Layout.fillHeight: true

            model: root.menuModel
            groupedModel: root.menuModel
            groupEditable: false        // read-only: kmenuedit owns authoring
            favoritesActive: false
            showRecentApps: false
            hideLabelsOnFavorites: false

            host: root.host
            adaptiveColumns: true
            sortFavoritesAlphabetically: false

            // Esc with no selection to clear → climb out one folder level. At the
            // root canGoBack is false, so the (re-enabled) window Shortcut closes.
            onEscapePressed: nav.goBack()
            // Folder activation drills in place (not the favourites overlay).
            onOpenFolderRequested: folderId => {
                if (root.menuModel)
                    root.menuModel.enterFolder(folderId)
            }
            onFolderContextMenuRequested: folderId => root.folderContextRequested(folderId.replace(/\/$/, ""))
        }
    }
}
