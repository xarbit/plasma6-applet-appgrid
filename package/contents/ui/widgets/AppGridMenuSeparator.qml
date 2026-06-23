/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Every conditional separator in AppGrid uses this instead of
    PlasmaComponents.MenuSeparator.

    Like PlasmaComponents.MenuItem, a MenuSeparator keeps its row height at
    visible=false, so a separator gated with `visible:` reserves a blank ghost
    row (a gap above/below an otherwise tight menu) (#200). Collapsing the height
    to 0 when hidden fixes it. Pairs with AppGridMenu / AppGridMenuItem.
*/

import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.MenuSeparator {
    height: visible ? implicitHeight : 0
}
