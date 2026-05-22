/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A vertically-scrolling pane: a Flickable with an auto-hiding overlay
    scroll bar (OverlayScrollBar), wrapping a margined ColumnLayout. Child
    objects declared inside go into the column.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Flickable {
    id: pane

    default property alias content: column.data

    readonly property real _margin: Kirigami.Units.largeSpacing * 2

    contentWidth: width
    contentHeight: column.implicitHeight + _margin * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    PlasmaComponents.ScrollBar.vertical: OverlayScrollBar {}

    ColumnLayout {
        id: column
        x: pane._margin
        y: pane._margin
        width: pane.width - pane._margin * 2
        spacing: 0
    }
}
