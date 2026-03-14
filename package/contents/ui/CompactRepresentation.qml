/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Panel icon representation with custom image support and size hints.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: root

    readonly property bool vertical: (Plasmoid.formFactor === PlasmaCore.Types.Vertical)
    readonly property bool useCustomButtonImage: (Plasmoid.configuration.useCustomButtonImage
        && Plasmoid.configuration.customButtonImage.length !== 0)

    onWidthChanged: updateSizeHints()
    onHeightChanged: updateSizeHints()

    function updateSizeHints() {
        if (useCustomButtonImage) {
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

    Kirigami.Icon {
        id: buttonIcon

        anchors.fill: parent

        active: mouseArea.containsMouse
        source: root.useCustomButtonImage
            ? Plasmoid.configuration.customButtonImage
            : Plasmoid.configuration.icon

        roundToIconSize: !root.useCustomButtonImage
            || (root.vertical ? implicitHeight / implicitWidth : implicitWidth / implicitHeight) === 1

        onSourceChanged: root.updateSizeHints()
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

        onClicked: {
            kicker.toggleWindow()
        }
    }
}
