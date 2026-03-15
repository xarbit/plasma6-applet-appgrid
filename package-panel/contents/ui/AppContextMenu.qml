/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Right-click context menu for grid items: favorite, pin, add to desktop, edit, hide.
*/

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

PlasmaComponents.Menu {
    id: contextMenu

    property var appsModel: null

    property int popupIndex: -1
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false

    function showForApp(index, storageId, desktopFile) {
        popupIndex = index
        popupStorageId = storageId
        popupDesktopFile = desktopFile
        popupIsFavorite = appsModel ? appsModel.isFavorite(storageId) : false
        popup()
    }

    PlasmaComponents.MenuItem {
        icon.name: contextMenu.popupIsFavorite ? "bookmark-remove" : "bookmark-new"
        text: contextMenu.popupIsFavorite ? i18n("Remove from Favorites") : i18n("Add to Favorites")
        onClicked: {
            if (contextMenu.appsModel) {
                contextMenu.appsModel.toggleFavorite(contextMenu.popupStorageId)
                Plasmoid.configuration.favoriteApps = contextMenu.appsModel.favoriteApps
            }
        }
        Accessible.name: text
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        icon.name: "pin"
        text: i18n("Pin to Task Manager")
        onClicked: Plasmoid.pinToTaskManager(contextMenu.popupStorageId)
        Accessible.name: i18n("Pin to Task Manager")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuItem {
        icon.name: "desktop"
        text: i18n("Add to Desktop")
        onClicked: Plasmoid.addToDesktop(contextMenu.popupDesktopFile)
        Accessible.name: i18n("Add to Desktop")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuItem {
        icon.name: "document-edit"
        text: i18n("Edit Application")
        onClicked: Plasmoid.editApplication(contextMenu.popupDesktopFile)
        Accessible.name: i18n("Edit Application")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        icon.name: "view-hidden"
        text: i18n("Hide Application")
        onClicked: {
            if (contextMenu.appsModel) {
                contextMenu.appsModel.hideApp(contextMenu.popupIndex)
                Plasmoid.configuration.hiddenApps = contextMenu.appsModel.hiddenApps
            }
        }
        Accessible.name: i18n("Hide Application")
        Accessible.role: Accessible.MenuItem
    }
}
