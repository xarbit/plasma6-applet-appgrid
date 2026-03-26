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
    property string appComment: ""
    property string installSource: ""
    property bool showTooltip: false
    property bool isCurrentItem: false
    property bool isNew: false
    property bool hideLabel: false
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
    readonly property var iconAnimFiles: [
        "",                          // 0=None
        "iconanims/ShakeAnim.qml",   // 1
        "iconanims/GrowAnim.qml",    // 2
        "iconanims/BounceAnim.qml",  // 3
        "iconanims/SpinAnim.qml"     // 4
        // 5=Shuffle handled separately via signal
    ]

    Loader {
        id: iconAnimLoader
        source: hoverAnimation > 0 && hoverAnimation < iconAnimFiles.length ? iconAnimFiles[hoverAnimation] : ""
        onLoaded: item.target = delegateIcon
    }

    function shake() {
        playAnimation()
    }

    function playAnimation() {
        if (Kirigami.Units.longDuration === 0) return
        if (hoverAnimation === 5) {
            shuffleRequested()
        } else if (iconAnimLoader.item) {
            iconAnimLoader.item.start()
        }
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.alignment: (root.hideLabel ? Qt.AlignVCenter : Qt.AlignTop) | Qt.AlignHCenter
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
            Layout.fillHeight: true
            visible: !root.hideLabel
            verticalAlignment: Text.AlignTop
            text: root.appName
            font: Kirigami.Theme.defaultFont
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

    // Tooltip with app name, description, and install source
    readonly property string tooltipText: {
        var parts = []
        if (root.appName)
            parts.push(root.appName)
        if (root.appComment)
            parts.push(root.appComment)
        else if (root.appGenericName && root.appGenericName !== root.appName)
            parts.push(root.appGenericName)
        if (root.installSource.length > 0)
            parts.push("Source: " + root.installSource)
        return parts.join("\n")
    }

    PlasmaComponents.ToolTip.text: root.tooltipText
    PlasmaComponents.ToolTip.visible: root.showTooltip && delegateMouse.containsMouse && !root.editMode
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

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

}
