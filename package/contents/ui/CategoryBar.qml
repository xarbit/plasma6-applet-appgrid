/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Horizontal category filter bar with "All" + dynamic categories.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: categoryBar

    property var appsModel: null

    Layout.fillWidth: true
    spacing: 0

    PlasmaComponents.ToolButton {
        Layout.fillWidth: true
        text: i18n("All")
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        checked: !categoryBar.appsModel || categoryBar.appsModel.filterCategory === ""
        onClicked: if (categoryBar.appsModel) categoryBar.appsModel.filterCategory = ""

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
            checked: categoryBar.appsModel && categoryBar.appsModel.filterCategory === modelData
            onClicked: if (categoryBar.appsModel) categoryBar.appsModel.filterCategory = modelData

            Accessible.name: modelData
            Accessible.role: Accessible.Button
        }
    }
}
