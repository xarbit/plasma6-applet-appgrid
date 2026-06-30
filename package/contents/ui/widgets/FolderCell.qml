/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A grid cell that renders a folder: a rounded tile holding a 2x2 mini-preview
    of its members' icons, plus the folder name below — styled to sit next to the
    app cells (AppIconDelegate). Source-agnostic: it is handed a name and a list
    of member icon names, so it serves both favourites folders and any future
    grouping (issue #18). Emits clicked(); opening is the caller's concern.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../js/themecolors.js" as ThemeColors

Item {
    id: root

    property string folderId: ""
    property string folderName: ""
    // Up to four member icon names for the preview, already resolved by the caller.
    property var memberIcons: []
    property int iconSize: Kirigami.Units.iconSizes.large
    property real fontScale: 1.0
    property bool hideLabel: false
    property bool isCurrentItem: false
    property bool hoverHighlight: true
    // Shared DragSource + this cell's grid row, so a folder can be drag-reordered
    // through the same path as app cells (issue #18).
    property var dragSource: null
    property int gridRow: -1

    // 2x2 preview geometry, as fractions of the tile (iconSize).
    readonly property real _previewInset: 0.12
    readonly property real _previewSpacing: 0.08
    readonly property real _removeIconScale: 0.6
    readonly property real _removeDimOpacity: 0.25

    signal clicked()
    signal contextRequested()

    function _beginDrag(handler) {
        if (!dragSource)
            return
        if (!handler.active) {
            dragSource.endDrag()
            return
        }
        // Internal reorder only — a folder has no app mime to advertise.
        dragSource.beginDrag(root, tile, ({}), handler, [], [])
    }

    // Soft hover / keyboard-current highlight — same treatment as AppIconDelegate.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.textColor, 0.06)
        visible: (root.hoverHighlight && hoverHandler.hovered) || root.isCurrentItem
    }

    // Fold target halo — a favourite is hovering to drop into this folder (#18).
    readonly property bool _isFoldTarget: root.dragSource && root.dragSource.isFoldTargetFolder(root.folderId)
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.3)
        border.width: 2
        border.color: Kirigami.Theme.highlightColor
        visible: root._isFoldTarget
    }

    // The folder tile's rect in this cell's coordinates — the drag-to-folder
    // target zone (#200): landing on it adds to the folder, the rest of the cell
    // reorders.
    readonly property rect iconRect: Qt.rect(contentLayout.x + tile.x,
                                             contentLayout.y + tile.y,
                                             tile.width, tile.height)

    ColumnLayout {
        id: contentLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // The folder tile: a rounded, faintly tinted square the size of an app
        // icon, holding the 2x2 preview inset by a small margin.
        Rectangle {
            id: tile
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
            radius: Kirigami.Units.cornerRadius
            color: ThemeColors.tint(Kirigami.Theme.textColor, 0.1)

            // Over the launcher's delete area → yield to a ✕ marker (#18/#193).
            readonly property bool _showRemoveMarker: root.dragSource
                && root.dragSource.dropWillRemove
                && root.dragSource.isSourceFolder(root.folderId)

            // Another favourite is hovering this folder to add to it (#200) →
            // the preview yields to a + marker, mirroring the app-icon fold.
            readonly property bool _showAddMarker: root.dragSource && root.dragSource.isFoldTargetFolder(root.folderId)

            GridLayout {
                anchors.fill: parent
                anchors.margins: Math.round(root.iconSize * root._previewInset)
                opacity: (parent._showRemoveMarker || parent._showAddMarker) ? root._removeDimOpacity : 1.0
                visible: !parent._showAddMarker
                columns: 2
                rowSpacing: Math.round(root.iconSize * root._previewSpacing)
                columnSpacing: Math.round(root.iconSize * root._previewSpacing)

                Repeater {
                    model: 4
                    Kirigami.Icon {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // var, not string: a member's icon may be a QIcon
                        // (a favourited KCM resolved from KAStats), not a name.
                        readonly property var _icon: index < root.memberIcons.length
                                                     ? root.memberIcons[index] : ""
                        source: _icon
                        visible: !!_icon
                    }
                }
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: root.iconSize * root._removeIconScale
                height: width
                visible: tile._showRemoveMarker
                source: "edit-delete-remove"
                color: Kirigami.Theme.negativeTextColor
            }

            // Add-to-folder marker: a favourite dwelled on this folder long enough
            // to arm a fold (#200) — replaces the preview, pops to confirm.
            FoldMarker {
                width: root.iconSize * root._removeIconScale
                height: width
                visible: tile._showAddMarker
                source: "list-add"
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.preferredHeight: lineCount === 1 ? implicitHeight * 2 : implicitHeight
            visible: !root.hideLabel
            text: root.folderName
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.fontScale
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            maximumLineCount: 2
            elide: Text.ElideRight
            wrapMode: Text.Wrap
        }
    }

    HoverHandler {
        id: hoverHandler
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.clicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.contextRequested()
    }

    DragHandler {
        id: folderDrag
        enabled: root.dragSource !== null
        target: null
        dragThreshold: 16
        onActiveChanged: root._beginDrag(this)
    }

    z: folderDrag.active ? 10 : 0
}
