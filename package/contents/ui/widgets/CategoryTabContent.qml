/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared contentItem for the category-bar tabs (All, the dynamic categories
    and Favorites). Shows an icon, a label, or both per the bar's display mode
    (#176); the visibility rules live in categorybardisplay.js so every tab
    agrees. Anchor tabs (Favorites, All) pass isAnchor to stay icon-only.

    The icon/label sit in a RowLayout centred inside this item, so the content
    stays centred when the owning button is stretched to fill the bar (the
    fill-width single-page layout) instead of packing to the left edge.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../js/categorybardisplay.js" as Display

Item {
    id: root

    required property var bar
    property string label: ""
    property string iconSource: ""
    // Anchor tabs (Favorites, All) are always icon-only regardless of mode.
    property bool isAnchor: false
    // Anchor tabs opt out of the Alt-held mnemonic rich text the category tabs use.
    property bool mnemonic: true
    property real iconSize: root.bar.buttonIconSize

    readonly property bool showsIcon: Display.showsIcon(root.bar.displayMode, root.isAnchor)
    readonly property bool showsText: Display.showsText(root.bar.displayMode, root.isAnchor)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            visible: root.showsIcon
            // The category icons are the monochrome freedesktop -symbolic
            // glyphs (same ones Kickoff uses), so they render flat and
            // theme-aware on their own — no isMask/tint needed.
            source: root.iconSource
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents.Label {
            readonly property bool rich: root.mnemonic && root.bar.altHeld
            visible: root.showsText
            Layout.alignment: Qt.AlignVCenter
            text: rich ? root.bar.mnemonicRichText(root.label) : root.label
            textFormat: rich ? Text.RichText : Text.PlainText
            font.pointSize: root.bar.buttonFontPointSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
