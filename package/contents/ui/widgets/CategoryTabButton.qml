/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    One category tab of the category bar (the delegate over its categories):
    selects the category, asks for the category's menu on a right-click in
    system categories mode, and arms open-on-hover.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.ToolButton {
    id: root

    // The CategoryBar this tab belongs to.
    required property var bar
    signal contextMenuRequested(string name)

    focusPolicy: Qt.NoFocus
    Layout.fillWidth: true
    Layout.fillHeight: true
    // Icon-only: never squish below the icon + padding; past
    // that the row overflows and scrolls.
    Layout.minimumWidth: root.bar.tabsIconOnly ? root.bar.tabMinWidth : 0
    required property int index
    required property string modelData
    Kirigami.MnemonicData.enabled: false
    leftPadding: root.bar.tabHPadding
    rightPadding: root.bar.tabHPadding
    text: ""
    contentItem: CategoryTabContent {
        bar: root.bar
        label: modelData
        iconSource: root.bar.appsModel
            ? root.bar.appsModel.categoryIcon(modelData) : ""
    }
    checked: !root.bar.wheelScrolling
             && !root.bar.favoritesActive
             && root.bar.selectedCategory === modelData
    onClicked: {
        root.bar.selectCategory(modelData)
        root.bar.scrollToSelected()
    }
    onHoveredChanged: hovered ? root.bar.hoverEnter(modelData)
                              : root.bar.hoverLeave(modelData)

    // Icon-only hides the label, so surface the category name
    // on hover; redundant when the label is already shown.
    PlasmaComponents.ToolTip.text: modelData
    PlasmaComponents.ToolTip.visible: hovered && root.bar.tabsIconOnly
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

    // The category's menu (system categories only).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function(mouse) {
            if (root.bar.appsModel && root.bar.appsModel.useSystemCategories)
                root.contextMenuRequested(root.modelData)
        }
    }

    Accessible.name: modelData
    Accessible.role: Accessible.Button
}
