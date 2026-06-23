/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Hosts an open favourites folder as a centered overlay card over the grid,
    wrapping a FolderContentsView (issue #18). Drag a member onto the area
    outside the card removes it from the folder.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: host

    property string folderName: ""
    property var members: []
    property var appsModel: null
    property var sharedFavoritesModel: null
    property int favoriteIdRole: -1
    property var dragSource: null
    property real iconSize: Kirigami.Units.iconSizes.large
    property real fontScale: 1.0
    property bool shadowEnabled: false
    property bool reduceGridSpacing: false
    property int hoverAnimation: 0
    property bool hoverHighlight: true
    // Main grid's column count + cell size, passed in by the host (the default is
    // a placeholder). The folder uses one fewer column at the same cell size, so
    // it fits with a drag-out margin (#18).
    property int columns: 5
    property real cellWidth: 0
    property real cellHeight: 0

    signal closeRequested()
    signal memberLaunched(string sid)
    signal memberRemoveRequested(string sid)
    signal memberContextRequested(string sid, string desktopFile)
    signal memberReorderRequested(int fromIndex, int toIndex)

    // The card spans at most this fraction of the grid's height; the content is
    // one column narrower than the grid so width rarely binds, but this caps it
    // just shy of the edges as a backstop.
    readonly property real _overlayFraction: 0.85
    readonly property real _overlayMaxWidthFraction: 0.98

    focus: true
    // Esc closes just the folder. The inner grid holds focus, so this catches the
    // Esc that bubbles up from it.
    Keys.onEscapePressed: closeRequested()

    // Give keyboard focus to the grid (not this host) and preselect the first
    // member, so arrow keys navigate and Enter launches right away on a keyboard
    // open. Runs after the child grid has built its model (children complete first).
    Component.onCompleted: {
        if (contents.count > 0)
            contents.currentIndex = 0
        contents.forceActiveFocus()
    }

    // Transparent catcher behind the card: tap outside to close, no dim. Uses a
    // hover-enabled MouseArea (not a bare TapHandler) so it also swallows hover
    // events — otherwise the grid underneath keeps showing its highlight through
    // the open folder (#200).
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: host.closeRequested()
    }

    // Drop a member onto the area outside the card → remove it from the folder.
    DropArea {
        anchors.fill: parent
        onDropped: drag => {
            if (!host.dragSource || !host.dragSource.isOwnDrag(drag))
                return
            const sid = host.dragSource.sourceStorageId
            if (!sid)
                return
            const inCard = drag.x >= card.x && drag.x <= card.x + card.width
                        && drag.y >= card.y && drag.y <= card.y + card.height
            if (!inCard)
                host.memberRemoveRequested(sid)
        }
    }

    // Plain themed card: colour, radius and a hairline border all come from the
    // theme's colour tokens, so it stays clean on every theme. View colour set =
    // the popup/content surface, opaque so the grid can't show through.
    Kirigami.ShadowedRectangle {
        id: card

        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        // Hairline border tinted from the (View) text colour.
        readonly property color _borderColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                                       Kirigami.Theme.textColor.g,
                                                       Kirigami.Theme.textColor.b, 0.15)

        // Centered, sized to the content (one column narrower than the grid, so it
        // already fits with a drag-out margin). Height caps so a big folder scrolls.
        readonly property real _overlayWidth: Math.min(parent.width * host._overlayMaxWidthFraction,
                                                        contents.implicitWidth + Kirigami.Units.largeSpacing * 2)
        readonly property real _overlayHeight: Math.min(parent.height * host._overlayFraction,
                                                         header.implicitHeight + contents.implicitHeight
                                                         + Kirigami.Units.largeSpacing * 3)

        anchors.centerIn: parent
        width: _overlayWidth
        height: _overlayHeight

        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.cornerRadius
        border.width: 1
        border.color: _borderColor
        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(0, 0, 0, 0.4)

        // Absorb stray clicks on the card chrome (title, gaps) so they don't fall
        // through to the click-catcher behind and close the folder.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
            onPressed: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Item {
                id: header
                Layout.fillWidth: true
                implicitHeight: closeButton.implicitHeight

                PlasmaComponents.Label {
                    // Centered across the whole card; kept clear of the close
                    // button so a long name never runs under it.
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - closeButton.width * 2 - Kirigami.Units.smallSpacing * 2)
                    text: host.folderName
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                PlasmaComponents.ToolButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon.name: "window-close-symbolic"
                    onClicked: host.closeRequested()
                }
            }

            FolderContentsView {
                id: contents
                Layout.fillHeight: true
                Layout.preferredWidth: implicitWidth
                Layout.alignment: Qt.AlignHCenter
                members: host.members
                appsModel: host.appsModel
                sharedFavoritesModel: host.sharedFavoritesModel
                favoriteIdRole: host.favoriteIdRole
                dragSource: host.dragSource
                preferredColumns: Math.max(1, host.columns - 1)
                mainCellWidth: host.cellWidth
                mainCellHeight: host.cellHeight
                iconSize: host.iconSize
                fontScale: host.fontScale
                shadowEnabled: host.shadowEnabled
                reduceGridSpacing: host.reduceGridSpacing
                hoverAnimation: host.hoverAnimation
                hoverHighlight: host.hoverHighlight
                onMemberLaunched: sid => host.memberLaunched(sid)
                onMemberContextRequested: (sid, df) => host.memberContextRequested(sid, df)
                onMemberReorderRequested: (from, to) => host.memberReorderRequested(from, to)
            }
        }
    }
}
