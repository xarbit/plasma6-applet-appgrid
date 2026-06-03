/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// Stable KAStats client id for favorites — survives plasmoid remove/re-add
// (Plasmoid.id changes each time), shared across both variants (#147).
var FAVORITES_CLIENT_ID = "dev.xarbit.appgrid.favorites"

// Plugin id of the panel-icon variant. Config pages use it to gate
// panel-only knobs that the centered variant ignores.
var PLUGIN_ID_PANEL = "dev.xarbit.appgrid.panel"

// Plugin id of the centered popup variant — also the default launcher
// icon name (the .desktop icon AppGrid ships under hicolor).
var PLUGIN_ID_CENTER = "dev.xarbit.appgrid"

// Alpha of the black scrim drawn behind the centered launcher when the
// "dim screen behind launcher" option is on (#170). The window is a
// fullscreen layer-shell surface, so the scrim covers everything under it.
var DIM_OVERLAY_OPACITY = 0.35
