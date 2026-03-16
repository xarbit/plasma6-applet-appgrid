/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable app icon delegate with configurable hover animation.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: root

    property string appName: ""
    property string appIcon: "application-x-executable"
    property string appGenericName: ""
    property bool isCurrentItem: false
    property bool isNew: false
    property real iconSize: Kirigami.Units.iconSizes.huge
    signal clicked(var mouse)

    // Visual icon override for shuffle animation (set externally by the grid)
    property string displayIcon: ""

    // Emitted when shuffle animation wants to swap with another icon
    signal shuffleRequested()

    // -- Edit/reorder mode --
    property bool editMode: false
    property bool isSelected: false
    signal removeRequested()

    // 0=None, 1=Shake, 2=Grow, 3=Bounce, 4=Spin, 5=Shuffle
    readonly property int hoverAnimation: Plasmoid.configuration.hoverAnimation

    function shake() {
        playAnimation()
    }

    function playAnimation() {
        if (hoverAnimation === 1) shakeAnim.start()
        else if (hoverAnimation === 2) growAnim.start()
        else if (hoverAnimation === 3) bounceAnim.start()
        else if (hoverAnimation === 4) spinAnim.start()
        else if (hoverAnimation === 5) shuffleRequested()
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            Kirigami.Icon {
                id: delegateIcon
                anchors.fill: parent
                source: root.displayIcon || root.appIcon || "application-x-executable"
                active: delegateMouse.containsMouse || root.isCurrentItem
                transformOrigin: Item.Center
            }

            // "New" badge dot
            Rectangle {
                visible: root.isNew
                width: Kirigami.Units.smallSpacing * 3
                height: width
                radius: width / 2
                color: Kirigami.Theme.positiveTextColor
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -Kirigami.Units.smallSpacing
                anchors.rightMargin: -Kirigami.Units.smallSpacing

                Accessible.ignored: true
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.appName
            font: Kirigami.Theme.smallFont
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Remove from favorites button (edit mode) — top-level so it captures clicks above delegateMouse
    MouseArea {
        id: removeBtn
        visible: root.editMode
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        x: Kirigami.Units.smallSpacing
        y: Kirigami.Units.smallSpacing
        z: 100
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.removeRequested()

        Kirigami.Icon {
            anchors.fill: parent
            source: "remove-symbolic"
        }

        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Remove from Favorites")
        PlasmaComponents.ToolTip.visible: removeBtn.containsMouse
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    // Selection highlight border
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: "transparent"
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
        visible: root.isSelected
    }

    MouseArea {
        id: delegateMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (!root.editMode)
                root.playAnimation()
        }

        onClicked: function(mouse) {
            root.clicked(mouse)
        }

        Accessible.name: root.appName + (root.isNew ? ", " + i18nd("dev.xarbit.appgrid", "new") : "")
        Accessible.role: Accessible.Button
        Accessible.description: root.appGenericName
        Accessible.focusable: true
    }

    // Wiggle animation for edit mode — animates entire delegate content
    SequentialAnimation {
        id: wiggleAnim
        loops: Animation.Infinite
        running: root.editMode
        NumberAnimation { target: contentLayout; property: "rotation"; from: -2; to: 2; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { target: contentLayout; property: "rotation"; from: 2; to: -2; duration: 150; easing.type: Easing.InOutQuad }
        onRunningChanged: {
            if (!running) contentLayout.rotation = 0
        }
    }

    // --- Shake animation ---
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 0;  to: 8;  duration: 50;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 8;  to: -7; duration: 90;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: -7; to: 5;  duration: 80;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 5;  to: -3; duration: 70;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: -3; to: 2;  duration: 60;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 2;  to: 0;  duration: 50;  easing.type: Easing.OutQuad }
    }

    // --- Grow animation ---
    SequentialAnimation {
        id: growAnim
        NumberAnimation { target: delegateIcon; property: "scale"; from: 1.0; to: 1.2; duration: 150; easing.type: Easing.OutBack }
        NumberAnimation { target: delegateIcon; property: "scale"; from: 1.2; to: 1.0; duration: 200; easing.type: Easing.InOutQuad }
    }

    // --- Bounce animation ---
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation { target: delegateIcon; property: "scale"; from: 1.0; to: 0.85; duration: 80;  easing.type: Easing.InQuad }
        NumberAnimation { target: delegateIcon; property: "scale"; from: 0.85; to: 1.15; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: delegateIcon; property: "scale"; from: 1.15; to: 0.95; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "scale"; from: 0.95; to: 1.0;  duration: 100; easing.type: Easing.OutQuad }
    }

    // --- Spin animation ---
    SequentialAnimation {
        id: spinAnim
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 0; to: 360; duration: 400; easing.type: Easing.InOutCubic }
        ScriptAction { script: delegateIcon.rotation = 0 }
    }
}
