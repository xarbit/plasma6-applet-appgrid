/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// Plugin id of the panel-icon variant. Config pages use it to gate
// panel-only knobs that the centered variant ignores.
var PLUGIN_ID_PANEL = "dev.xarbit.appgrid.panel"

// Plugin id of the centered popup variant — also the default launcher
// icon name (the .desktop icon AppGrid ships under hicolor).
var PLUGIN_ID_CENTER = "dev.xarbit.appgrid"

// Freedesktop fallback icon, shown when an app exposes no icon name.
var DEFAULT_ICON = "application-x-executable"

// Row opacity for a hidden app shown in search results (when "show hidden in
// search" is on): dimmed enough to read as hidden, legible enough to still pick.
var HIDDEN_RESULT_OPACITY = 0.55

// hoverAnimation config values (config/main.xml + the Appearance page's combo
// order). The sort modes are the C++ AppFilterModel.SortMode enum.
var HoverAnimation = {
    None: 0,
    Shake: 1,
    Grow: 2,
    Bounce: 3,
    Spin: 4,
    Shuffle: 5,
}
