/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A wrapping result-row label that expands in place when its row is selected:
    a few lines while collapsed (sized to fit the row without growing it) and
    more while expanded (the row grows so the text can be read). Used for runner
    results whose text is a paragraph, e.g. the dictionary runner (#183).

    Centralises the height-for-width handling QtQuick.Layouts does NOT do on its
    own: the wrapped height is fed back through Layout.preferredHeight, and the
    expanded row drops eliding so implicitHeight reports the real wrapped height
    instead of measuring itself to fit a single line.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.Label {
    // Show the text up to expandedLines instead of collapsedLines.
    property bool expanded: false
    property int collapsedLines: 1
    property int expandedLines: 8

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    wrapMode: Text.WordWrap
    maximumLineCount: expanded ? expandedLines : collapsedLines
    elide: expanded ? Text.ElideNone : Text.ElideRight
}
