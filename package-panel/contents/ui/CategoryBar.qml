/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Horizontal category filter bar with favorites, "All", and dynamic categories.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

RowLayout {
    id: categoryBar

    property var appsModel: null
    property bool favoritesActive: false
    readonly property bool favoritesFirst: Plasmoid.configuration.startWithFavorites || false

    signal favoritesToggled(bool active)

    Layout.fillWidth: true
    spacing: 0

    PlasmaComponents.ToolButton {
        id: favButtonLeft
        visible: categoryBar.favoritesFirst
        icon.name: "folder-favorites"
        checked: categoryBar.favoritesActive
        onClicked: categoryBar.favoritesToggled(!categoryBar.favoritesActive)

        PlasmaComponents.ToolTip.text: i18n("Favorites")
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18n("Favorites")
        Accessible.role: Accessible.Button
    }

    PlasmaComponents.ToolButton {
        Layout.fillWidth: true
        text: i18n("All")
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        checked: !categoryBar.favoritesActive
                 && (!categoryBar.appsModel || categoryBar.appsModel.filterCategory === "")
        onClicked: {
            if (categoryBar.favoritesActive)
                categoryBar.favoritesToggled(false)
            if (categoryBar.appsModel)
                categoryBar.appsModel.filterCategory = ""
        }

        Accessible.name: i18n("All applications")
        Accessible.role: Accessible.Button
    }

    Repeater {
        model: categoryBar.appsModel ? categoryBar.appsModel.categories() : []
        delegate: PlasmaComponents.ToolButton {
            Layout.fillWidth: true
            required property string modelData
            text: modelData
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
            checked: !categoryBar.favoritesActive
                     && categoryBar.appsModel && categoryBar.appsModel.filterCategory === modelData
            onClicked: {
                if (categoryBar.favoritesActive)
                    categoryBar.favoritesToggled(false)
                if (categoryBar.appsModel)
                    categoryBar.appsModel.filterCategory = modelData
            }

            Accessible.name: modelData
            Accessible.role: Accessible.Button
        }
    }

    PlasmaComponents.ToolButton {
        id: favButtonRight
        visible: !categoryBar.favoritesFirst
        icon.name: "folder-favorites"
        checked: categoryBar.favoritesActive
        onClicked: categoryBar.favoritesToggled(!categoryBar.favoritesActive)

        PlasmaComponents.ToolTip.text: i18n("Favorites")
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

        Accessible.name: i18n("Favorites")
        Accessible.role: Accessible.Button
    }
}
