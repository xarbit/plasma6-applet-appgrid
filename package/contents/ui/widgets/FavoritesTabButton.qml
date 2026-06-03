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

    required property var categoryBar

    // Match the scaled height/icon of the rest of the category bar (#171).
    Layout.preferredHeight: root.categoryBar.buttonHeight
    icon.name: "bookmarks-bookmarked"
    icon.width: root.categoryBar.buttonIconSize
    icon.height: root.categoryBar.buttonIconSize
    checked: root.categoryBar.favoritesActive
    onClicked: root.categoryBar.selectFavorites()

    PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Favorites")
    PlasmaComponents.ToolTip.visible: hovered
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

    Accessible.name: i18nd("dev.xarbit.appgrid", "Favorites")
    Accessible.role: Accessible.Button

    FavoritesTabDragHover { target: root.categoryBar }
}
