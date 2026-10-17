/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A simple centered empty-state: a large dimmed icon over a wrapped label.
    Stands in for Kirigami.PlaceholderMessage, which fails to load on some
    Kirigami builds (IconPropertiesGroup type clash) and took the whole panel
    down with it. Set iconSource + text; size/position it from the caller.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami

ColumnLayout {
    property alias iconSource: icon.source
    property alias text: label.text

    spacing: Kirigami.Units.largeSpacing

    Kirigami.Icon {
        id: icon
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Kirigami.Units.iconSizes.huge
        implicitHeight: Kirigami.Units.iconSizes.huge
        opacity: 0.6
    }
    QQC2.Label {
        id: label
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.7
    }
}
