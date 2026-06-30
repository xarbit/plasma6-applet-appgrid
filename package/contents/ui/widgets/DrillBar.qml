/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared drill header for the in-place folder views (favourites #18, menu #201):
    a Back button + the current folder name. While a drag is in flight, hovering
    the header highlights it and, after a short dwell, springs back one level so
    the item can be sorted (or dropped) in the parent — and a direct drop here
    takes the member out of the open folder (editable views only).

    Driven by any navigable grouped model that exposes canGoBack /
    currentFolderName / goBack().
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../js/themecolors.js" as ThemeColors

Item {
    id: bar

    property var model: null
    property var dragSource: null
    property bool editable: false

    signal removeMemberRequested(string sid)

    // Spring-loaded back: a drag must dwell this long over the header before it
    // navigates up, so a quick pass-through doesn't. Matches the fold dwell.
    readonly property int springDwellMs: 500
    property bool _springArmed: false

    visible: !!model && model.canGoBack
    implicitHeight: visible ? row.implicitHeight : 0

    // Drag-over highlight (feedback during the dwell).
    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.25)
        opacity: bar._springArmed ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.ToolButton {
            icon.name: "go-previous-symbolic"
            text: i18nd("dev.xarbit.appgrid", "Back")
            onClicked: if (bar.model) bar.model.goBack()
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: bar.model ? bar.model.currentFolderName : ""
            font.bold: true
            elide: Text.ElideRight
        }
    }

    Timer {
        id: dwellTimer
        interval: bar.springDwellMs
        onTriggered: {
            bar._springArmed = false
            if (!bar.model)
                return
            // Spring up: take the member out of the folder (now a loose top-level
            // item) and go up, keeping the drag alive. The parent grid's live
            // reorder then reflows/animates it under the cursor and fold-into-
            // another-folder works, just like any favourite drag. #18
            if (bar.editable && bar.dragSource && bar.dragSource.sourceStorageId && bar.model.currentPath)
                bar.removeMemberRequested(bar.dragSource.sourceStorageId)
            bar.model.goBack()
        }
    }

    // Drag onto the header. Sits above the row but only claims drag events, so
    // the Back button still gets clicks.
    DropArea {
        anchors.fill: parent
        enabled: bar.dragSource !== null
        onEntered: {
            bar._springArmed = true
            dwellTimer.restart()
        }
        onExited: {
            bar._springArmed = false
            dwellTimer.stop()
        }
        onDropped: drag => {
            dwellTimer.stop()
            bar._springArmed = false
            // A direct drop (no dwell) takes the member out of the folder.
            if (!bar.editable || !bar.dragSource || !bar.dragSource.isOwnDrag(drag))
                return
            const sid = bar.dragSource.sourceStorageId
            if (sid)
                bar.removeMemberRequested(sid)
        }
    }
}
