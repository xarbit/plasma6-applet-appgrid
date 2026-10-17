/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A highlight drawn behind a grid cell's content (an app or a folder), built
    only while it shows. One look per kind:

      * Hover      — soft neutral fill, like Dolphin's icon-view hover
                     (QPalette::Text at alpha 0.06, rounded, borderless); also
                     marks the keyboard cursor.
      * Selected   — accent fill and border of a multi-selected cell.
      * Anchor     — Selected with a stronger border: the selection's anchor.
      * FoldTarget — strong accent ring: a favourite dropping into the cell
                     makes or joins a folder (#18).
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../js/themecolors.js" as ThemeColors

Loader {
    id: root

    enum Kind { Hover, Selected, Anchor, FoldTarget }

    property int kind: CellHighlight.Hover
    property bool shown: false

    anchors.fill: parent
    anchors.margins: Kirigami.Units.smallSpacing
    active: shown

    sourceComponent: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: root.kind === CellHighlight.Hover ? ThemeColors.tint(Kirigami.Theme.textColor, 0.06)
             : root.kind === CellHighlight.FoldTarget ? ThemeColors.tint(Kirigami.Theme.highlightColor, 0.3)
             : ThemeColors.tint(Kirigami.Theme.highlightColor, 0.18)
        border.width: root.kind === CellHighlight.Hover ? 0
                    : root.kind === CellHighlight.Selected ? 1
                    : 2
        border.color: root.kind === CellHighlight.FoldTarget ? Kirigami.Theme.highlightColor
                    : ThemeColors.tint(Kirigami.Theme.highlightColor, root.kind === CellHighlight.Anchor ? 0.9 : 0.55)
    }
}
