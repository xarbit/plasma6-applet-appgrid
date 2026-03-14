/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable app icon delegate with shake animation on hover and grid open.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    property string appName: ""
    property string appIcon: "application-x-executable"
    property string appGenericName: ""
    property bool isCurrentItem: false
    property bool isNew: false
    property real iconSize: Kirigami.Units.iconSizes.huge
    signal clicked(var mouse)

    function shake() {
        shakeAnim.start()
    }

    ColumnLayout {
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
                source: root.appIcon || "application-x-executable"
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

    MouseArea {
        id: delegateMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: shakeAnim.start()
        onClicked: function(mouse) { root.clicked(mouse) }

        Accessible.name: root.appName + (root.isNew ? ", " + i18n("new") : "")
        Accessible.role: Accessible.Button
        Accessible.description: root.appGenericName
        Accessible.focusable: true
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 0;  to: 8;  duration: 50;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 8;  to: -7; duration: 90;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: -7; to: 5;  duration: 80;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 5;  to: -3; duration: 70;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: -3; to: 2;  duration: 60;  easing.type: Easing.InOutQuad }
        NumberAnimation { target: delegateIcon; property: "rotation"; from: 2;  to: 0;  duration: 50;  easing.type: Easing.OutQuad }
    }
}
