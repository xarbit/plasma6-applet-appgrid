/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A wrapping result-row label, capped at `lines` and elided. Centralises the
    height-for-width handling QtQuick.Layouts does NOT do on its own: the wrapped
    height is fed back through Layout.preferredHeight so a row sizes to the real
    wrapped text instead of measuring itself to one line.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.Label {
    property int lines: 1

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    wrapMode: Text.WordWrap
    maximumLineCount: lines
    elide: Text.ElideRight
}
