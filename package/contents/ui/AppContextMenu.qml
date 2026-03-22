/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Right-click context menu for grid items: favorite, pin, add to desktop, edit, hide.
*/

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmaComponents.Menu {
    id: contextMenu

    Kicker.ProcessRunner { id: processRunner }

    property var appsModel: null

    property int popupIndex: -1
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false

    property var popupActions: []

    function showForApp(index, storageId, desktopFile) {
        popupIndex = index
        popupStorageId = storageId
        popupDesktopFile = desktopFile
        popupIsFavorite = appsModel ? appsModel.isFavorite(storageId) : false
        popupActions = Plasmoid.appActions(storageId) || []
        popup()
    }

    // -- Application-defined actions (jumplist) --
    Repeater {
        model: contextMenu.popupActions
        delegate: PlasmaComponents.MenuItem {
            required property var modelData
            required property int index
            icon.name: modelData.icon || ""
            text: modelData.text
            onClicked: {
                Plasmoid.launchAppAction(contextMenu.popupStorageId, index)
                contextMenu.close()
            }
        }
    }

    PlasmaComponents.MenuItem {
        icon.name: contextMenu.popupIsFavorite ? "bookmark-remove" : "bookmark-new"
        text: contextMenu.popupIsFavorite ? i18nd("dev.xarbit.appgrid", "Remove from Favorites") : i18nd("dev.xarbit.appgrid", "Add to Favorites")
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
        text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        onClicked: Plasmoid.pinToTaskManager(contextMenu.popupStorageId)
        Accessible.name: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuItem {
        icon.name: "desktop"
        text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
        onClicked: Plasmoid.addToDesktop(contextMenu.popupDesktopFile)
        Accessible.name: i18nd("dev.xarbit.appgrid", "Add to Desktop")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuItem {
        icon.name: "document-edit"
        text: i18nd("dev.xarbit.appgrid", "Edit Application")
        onClicked: processRunner.runMenuEditor(contextMenu.popupStorageId)
        Accessible.name: i18nd("dev.xarbit.appgrid", "Edit Application")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        icon.name: "view-hidden"
        text: i18nd("dev.xarbit.appgrid", "Hide Application")
        onClicked: {
            if (contextMenu.appsModel) {
                contextMenu.appsModel.hideApp(contextMenu.popupIndex)
                Plasmoid.configuration.hiddenApps = contextMenu.appsModel.hiddenApps
            }
        }
        Accessible.name: i18nd("dev.xarbit.appgrid", "Hide Application")
        Accessible.role: Accessible.MenuItem
    }
}
