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
    Kicker.ContainmentInterface { id: containmentInterface }

    property var appletInterface: null
    property var appsModel: null
    property var sharedFavoritesModel: null

    property int popupIndex: -1
    property string popupStorageId: ""
    property string popupDesktopFile: ""
    property bool popupIsFavorite: false

    property var popupActions: []

    function showForApp(index, storageId, desktopFile) {
        popupIndex = index
        popupStorageId = storageId
        popupDesktopFile = desktopFile
        const prefixed = storageId.indexOf(":") >= 0 ? storageId : "applications:" + storageId
        popupIsFavorite = sharedFavoritesModel
                          ? sharedFavoritesModel.isFavorite(prefixed)
                          : false
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
        // Disabled while a drag-reorder is mid-flight to avoid clobbering
        // KAStats state and stale-grabbing the in-progress move.
        enabled: !(contextMenu.appletInterface
                   && contextMenu.appletInterface.favoritesDragProxy
                   && contextMenu.appletInterface.favoritesDragProxy.Drag.active)
        onClicked: {
            const sid = contextMenu.popupStorageId
            if (!sid) return
            if (contextMenu.sharedFavoritesModel) {
                const prefixed = sid.indexOf(":") >= 0 ? sid : "applications:" + sid
                if (contextMenu.sharedFavoritesModel.isFavorite(prefixed))
                    contextMenu.sharedFavoritesModel.removeFavorite(prefixed)
                else
                    contextMenu.sharedFavoritesModel.addFavorite(prefixed)
            }
        }
        Accessible.name: text
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuSeparator {}

    PlasmaComponents.MenuItem {
        icon.name: "pin"
        text: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        onClicked: containmentInterface.addLauncher(contextMenu.appletInterface, Kicker.ContainmentInterface.TaskManager, contextMenu.popupDesktopFile)
        Accessible.name: i18nd("dev.xarbit.appgrid", "Pin to Task Manager")
        Accessible.role: Accessible.MenuItem
    }

    PlasmaComponents.MenuItem {
        icon.name: "desktop"
        text: i18nd("dev.xarbit.appgrid", "Add to Desktop")
        onClicked: containmentInterface.addLauncher(contextMenu.appletInterface, Kicker.ContainmentInterface.Desktop, contextMenu.popupDesktopFile)
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
