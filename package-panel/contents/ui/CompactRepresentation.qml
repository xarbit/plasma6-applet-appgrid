/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Panel icon representation with custom image support, optional text label,
    and size hints.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: root

    readonly property bool vertical: (Plasmoid.formFactor === PlasmaCore.Types.Vertical)
    readonly property bool useCustomButtonImage: (Plasmoid.configuration.useCustomButtonImage
        && Plasmoid.configuration.customButtonImage.length !== 0)
    readonly property bool shouldHaveLabel: !vertical
        && Plasmoid.configuration.menuLabel !== undefined
        && Plasmoid.configuration.menuLabel !== ""
    readonly property bool shouldHaveIcon: vertical || Plasmoid.configuration.icon !== ""
        || useCustomButtonImage

    readonly property bool tooSmall: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        && Math.round(2 * (root.height / 5)) <= Kirigami.Theme.smallFont.pixelSize

    onWidthChanged: updateSizeHints()
    onHeightChanged: updateSizeHints()

    function updateSizeHints() {
        if (shouldHaveLabel) {
            var iconWidth = shouldHaveIcon ? Math.min(root.height, Kirigami.Units.iconSizes.huge) : 0
            var labelWidth = labelTextField.contentWidth + labelTextField.Layout.leftMargin + labelTextField.Layout.rightMargin
            var totalWidth = iconWidth + labelWidth
            root.Layout.minimumWidth = totalWidth
            root.Layout.minimumHeight = -1
            root.Layout.maximumWidth = totalWidth
            root.Layout.maximumHeight = Kirigami.Units.iconSizes.huge
        } else if (useCustomButtonImage) {
            if (vertical) {
                const scaledHeight = Math.floor(parent.width * (buttonIcon.implicitHeight / buttonIcon.implicitWidth));
                root.Layout.minimumWidth = -1;
                root.Layout.minimumHeight = scaledHeight;
                root.Layout.maximumWidth = Kirigami.Units.iconSizes.huge;
                root.Layout.maximumHeight = scaledHeight;
            } else {
                const scaledWidth = Math.floor(parent.height * (buttonIcon.implicitWidth / buttonIcon.implicitHeight));
                root.Layout.minimumWidth = scaledWidth;
                root.Layout.minimumHeight = -1;
                root.Layout.maximumWidth = scaledWidth;
                root.Layout.maximumHeight = Kirigami.Units.iconSizes.huge;
            }
        } else {
            root.Layout.minimumWidth = -1;
            root.Layout.minimumHeight = -1;
            root.Layout.maximumWidth = Kirigami.Units.iconSizes.huge;
            root.Layout.maximumHeight = Kirigami.Units.iconSizes.huge;
        }
    }

    RowLayout {
        id: iconLabelRow
        anchors.fill: parent
        spacing: 0

        Kirigami.Icon {
            id: buttonIcon

            Layout.fillHeight: true
            Layout.preferredWidth: shouldHaveLabel
                ? Math.min(root.height, Kirigami.Units.iconSizes.huge)
                : root.width

            visible: root.shouldHaveIcon

            active: mouseArea.containsMouse
            source: root.useCustomButtonImage
                ? Plasmoid.configuration.customButtonImage
                : Plasmoid.configuration.icon

            roundToIconSize: !root.useCustomButtonImage
                || (root.vertical ? implicitHeight / implicitWidth : implicitWidth / implicitHeight) === 1

            onSourceChanged: root.updateSizeHints()
        }

        PlasmaComponents.Label {
            id: labelTextField

            Layout.fillHeight: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing

            visible: root.shouldHaveLabel

            text: Plasmoid.configuration.menuLabel || ""
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.NoWrap
            fontSizeMode: Text.VerticalFit
            font.pixelSize: root.tooSmall
                ? Kirigami.Theme.defaultFont.pixelSize
                : Kirigami.Units.iconSizes.roundedIconSize(Kirigami.Units.gridUnit * 2)
            minimumPointSize: Kirigami.Theme.smallFont.pointSize

            onContentWidthChanged: root.updateSizeHints()
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true

        Accessible.name: Plasmoid.title
        Accessible.role: Accessible.Button

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Enter:
            case Qt.Key_Return:
            case Qt.Key_Select:
                Plasmoid.activated();
                break;
            }
        }

        onClicked: Plasmoid.activated()
    }
}
