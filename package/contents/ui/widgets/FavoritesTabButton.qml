/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// The Favorites tab button. Favorites sit on the left when favoritesFirst
// is set and on the right otherwise; both placements share this one
// definition. Clicking always *selects* favorites (never toggles back to
// All — the dedicated All button is for that), see #169.
PlasmaComponents.ToolButton {
    id: root

    required property var bar

    // Keep focus on the search field so Alt+arrow nav survives a click (#174).
    focusPolicy: Qt.NoFocus

    Layout.preferredHeight: root.bar.buttonHeight

    // Anchor tab: always icon-only, so drop the vertical padding and let the
    // glyph fill the button height (#171) at the shared anchor icon size.
    topPadding: 0
    bottomPadding: 0

    contentItem: CategoryTabContent {
        bar: root.bar
        label: root.bar.favoritesLabel
        iconSource: "bookmarks-symbolic"
        isAnchor: true
        mnemonic: false
        iconSize: root.bar.anchorIconSize
    }

    checked: root.bar.favoritesActive && !root.bar.wheelScrolling
    onClicked: root.bar.selectFavorites()
    onHoveredChanged: hovered ? root.bar.hoverEnter(root.bar.favoritesLabel)
                              : root.bar.hoverLeave(root.bar.favoritesLabel)

    PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Favorites")
    PlasmaComponents.ToolTip.visible: hovered
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

    Accessible.name: i18nd("dev.xarbit.appgrid", "Favorites")
    Accessible.role: Accessible.Button

    FavoritesTabDragHover { target: root.bar }
}
