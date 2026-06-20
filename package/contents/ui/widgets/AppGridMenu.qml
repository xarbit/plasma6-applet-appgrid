/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Every menu in AppGrid uses this instead of PlasmaComponents.Menu.

    PlasmaComponents.Menu sizes itself to max(KSvg-background.implicitHeight,
    content) + padding, so the background frame's minimum height bleeds through
    as dead space below short menus (a one- or two-item menu gets a blank gap at
    the bottom). Forcing content-driven height fixes it. This lived inline on a
    single menu and was repeatedly forgotten on new ones (#200), so it now lives
    in one component that all menus inherit and can't regress.
*/

import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.Menu {
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
}
