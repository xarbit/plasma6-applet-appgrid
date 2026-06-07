/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable app icon delegate with configurable hover animation.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../js/themecolors.js" as ThemeColors
import "../js/constants.js" as Const

Item {
    id: root

    property string appName: ""
    property string appIcon: Const.DEFAULT_ICON
    property string appGenericName: ""
    property string appComment: ""
    property string installSource: ""
    property bool showTooltip: false
    property bool hoverHighlight: true
    property bool isCurrentItem: false
    property bool isNew: false
    property bool hideLabel: false
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Multiplier on the label font, following the size preset (Scale.textScale).
    // Pinned to 1.0 when text size is decoupled from the preset (#167).
    property real fontScale: 1.0
    // Identity used by the favorites drag controller. Set externally;
    // empty disables dragging when desktopFile is also empty.
    property string storageId: ""
    // Absolute path to the .desktop file for this app. Used to advertise
    // a text/uri-list MIME entry so external targets (taskbar, panel,
    // Dolphin, desktop) accept the dropped app.
    property string desktopFile: ""
    property int gridRow: -1
    // Shared DragSource that carries the grab image and mime data while this
    // delegate is being dragged. Same pattern as Kickoff's `dragSource` (see
    // BUG 449426). When null, dragging is disabled entirely.
    property DragSource dragSource: null

    // -- Multi-select visuals --
    // Set by the owning GridView when this delegate's storageId is in the
    // selection set. Drives the accent halo + checkmark badge below.
    property bool selected: false
    // True when this delegate is the current selection anchor (last toggle).
    // A subtle dotted ring distinguishes it from plain selected items so
    // the user knows where Shift+click / Shift+Arrow will pivot from.
    property bool selectionAnchor: false

    // Parallel lists of storageIds and file:// URLs for the active multi-
    // selection. Populated by the owning GridView only when `selected` is
    // true so each delegate carries the bundle it would advertise if a
    // drag started here. Empty/length-1 falls back to single-item drag.
    property list<string> multiSelectionSids: []
    property list<string> multiSelectionUrls: []
    // Icon names parallel to multiSelectionSids — DragSource uses these to
    // render the stacked drag-preview pixmap for multi-item drags.
    property list<string> multiSelectionIcons: []
    signal clicked(var mouse)

    // Visual icon override for shuffle animation (set externally by the grid)
    property string displayIcon: ""

    // Emitted when shuffle animation wants to swap with another icon
    signal shuffleRequested()

    // 0=None, 1=Shake, 2=Grow, 3=Bounce, 4=Spin, 5=Shuffle
    required property int hoverAnimation
    required property bool shadowEnabled
    readonly property var iconAnimFiles: [
        "",                          // 0=None
        "../iconanims/ShakeAnim.qml",   // 1
        "../iconanims/GrowAnim.qml",    // 2
        "../iconanims/BounceAnim.qml",  // 3
        "../iconanims/SpinAnim.qml"     // 4
        // 5=Shuffle handled separately via signal
    ]

    Loader {
        id: iconAnimLoader
        // Async so building a screenful of delegates on open does not block
        // on instantiating one animation object per icon.
        asynchronous: true
        source: hoverAnimation > 0 && hoverAnimation < iconAnimFiles.length ? iconAnimFiles[hoverAnimation] : ""
        onLoaded: {
            item.target = delegateIcon
            // All icon animations share the IconAnimBase contract; only Grow
            // reacts to hovered, the rest ignore it.
            item.hovered = Qt.binding(function() { return delegateMouse.containsMouse })
        }
    }

    function shake() {
        playAnimation()
    }

    function playAnimation() {
        if (Kirigami.Units.longDuration === 0) return
        if (hoverAnimation === 5) {
            shuffleRequested()
        } else if (iconAnimLoader.item) {
            iconAnimLoader.item.start()
        }
    }

    // Highlight background shown while this delegate is being dragged.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.highlightColor
        opacity: 0.25
        visible: pointerDrag.active || touchDrag.active
    }

    // Soft hover / keyboard-current highlight — neutral grey fill, no border,
    // matching Dolphin's icon-view hover (KItemListWidget draws an unselected
    // hover as QPalette::Text at alpha 0.06, rounded, borderless). Mouse hover
    // is gated by hoverHighlight; keyboard navigation always shows it so the
    // current item stays visible. Multi-selection uses the accent halo below.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.textColor, 0.06)
        visible: ((root.hoverHighlight && delegateMouse.containsMouse) || root.isCurrentItem)
                 && !root.selected && !(pointerDrag.active || touchDrag.active)
    }

    // -- Multi-select halo --
    // Persistent accent fill+border for items in the selection. Sits below
    // the content (z is default) so the icon and label stay legible.
    Rectangle {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.18)
        border.width: root.selectionAnchor ? 2 : 1
        border.color: ThemeColors.tint(Kirigami.Theme.highlightColor,
                                       root.selectionAnchor ? 0.9 : 0.55)
        visible: root.selected && !(pointerDrag.active || touchDrag.active)
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.alignment: (root.hideLabel ? Qt.AlignVCenter : Qt.AlignTop) | Qt.AlignHCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            ShadowedIcon {
                id: delegateIcon
                anchors.fill: parent
                source: root.displayIcon || root.appIcon || Const.DEFAULT_ICON
                shadowEnabled: root.shadowEnabled
                // No icon brighten — hover is shown by the Rectangle above (#106).
                active: false
                transformOrigin: Item.Center
            }

            // "New" badge dot
            Rectangle {
                visible: root.isNew
                width: Kirigami.Units.smallSpacing * 3
                height: width
                radius: width / 2
                color: Kirigami.Theme.positiveTextColor
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -Kirigami.Units.smallSpacing
                anchors.rightMargin: -Kirigami.Units.smallSpacing

                Accessible.ignored: true
            }

        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hideLabel
            verticalAlignment: Text.AlignTop
            text: root.appName
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * root.fontScale
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // Tooltip (app name, description, install source) — built lazily on hover
    // rather than eagerly per delegate at grid build.
    function _tooltipText() {
        var parts = []
        if (root.appName)
            parts.push(root.appName)
        if (root.appComment)
            parts.push(root.appComment)
        else if (root.appGenericName && root.appGenericName !== root.appName)
            parts.push(root.appGenericName)
        if (root.installSource.length > 0)
            parts.push(i18nd("dev.xarbit.appgrid", "Source: %1", root.installSource))
        return parts.join("\n")
    }

    PlasmaComponents.ToolTip.text: (root.showTooltip && delegateMouse.containsMouse) ? root._tooltipText() : ""
    PlasmaComponents.ToolTip.visible: root.showTooltip && delegateMouse.containsMouse
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

    MouseArea {
        id: delegateMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: (pointerDrag.active || touchDrag.active)
                     ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        onEntered: root.playAnimation()

        onClicked: function(mouse) {
            root.clicked(mouse)
        }

        onPressAndHold: function(mouse) {
            root.clicked({ button: Qt.RightButton, x: mouse.x, y: mouse.y })
        }

        Accessible.name: root.appName
            + (root.isNew ? ", " + i18nd("dev.xarbit.appgrid", "new") : "")
            + (root.selected ? ", " + i18nd("dev.xarbit.appgrid", "selected") : "")
        Accessible.role: Accessible.Button
        Accessible.description: root.appGenericName
        Accessible.focusable: true
    }

    // QUrl typed property for the .desktop file. The Drag.mimeData array form
    // of text/uri-list requires QUrl values (not strings), so we bind once
    // here so QML does the string → url conversion at the property boundary.
    readonly property url desktopFileUrl: root.desktopFile.length > 0
        ? "file://" + root.desktopFile : ""

    // -- Drag handler for favorites reordering and external drag-out --
    // A DragHandler on this delegate activates the shared DragSource (see
    // appgrid.dragSource / DragSource.qml). Internal reorder identifies "our"
    // drags via dragSource.isOwnDrag(drag) and reads dragSource.sourceItem
    // (set to this delegate). External drop targets receive `text/uri-list`
    // pointing at the app's .desktop file.
    function _beginDrag(handler) {
        if (!root.dragSource) return
        if (!handler.active) {
            root.dragSource.endDrag()
            return
        }
        // Multi-drag activates only when this delegate is part of a 2+ item
        // selection. DragSource caches the sid list so internal reorder can
        // opt out; external targets (Plasma panel, Dolphin) consume the
        // multi-entry text/uri-list directly.
        const isMulti = root.selected
                        && root.multiSelectionUrls.length > 1
                        && root.multiSelectionSids.length > 1
        let mime = {}
        if (isMulti) {
            // Newline-joined wire format per RFC 2483. The single-item
            // path below relies on a `property url` for QString → QUrl
            // coercion at the property boundary; that trick doesn't work
            // for a JS array (Qt won't bulk-coerce its elements), so we
            // pass the RFC text form instead — QMimeData parses it into
            // QList<QUrl> on the drop side.
            mime["text/uri-list"] = root.multiSelectionUrls.join("\r\n")
        } else if (root.desktopFileUrl.toString().length > 0) {
            mime["text/uri-list"] = [root.desktopFileUrl]
        }
        const sids = isMulti ? root.multiSelectionSids : []
        const icons = isMulti ? root.multiSelectionIcons : []
        root.dragSource.beginDrag(root, delegateIcon, mime, handler, sids, icons)
    }

    DragHandler {
        id: pointerDrag
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        enabled: root.dragSource !== null
                 && (root.storageId.length > 0 || root.desktopFile.length > 0)
        target: null
        // Higher than the Qt default to avoid accidental drags on jittery
        // touchpads and high-DPI scrolling.
        dragThreshold: 16
        onActiveChanged: root._beginDrag(this)
    }

    DragHandler {
        id: touchDrag
        acceptedDevices: PointerDevice.TouchScreen
        enabled: pointerDrag.enabled
        target: null
        // Both axes free — favorites grid reorders in 2D, unlike the list
        // views in upstream Kickoff that only need a single axis.
        dragThreshold: 24
        onActiveChanged: root._beginDrag(this)
    }

    // Lift delegate above siblings while dragging
    z: (pointerDrag.active || touchDrag.active) ? 10 : 0
}
