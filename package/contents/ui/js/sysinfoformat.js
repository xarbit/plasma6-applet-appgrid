/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Formats the system-info block for PrefixInfoView's "Copy to Clipboard"
    button. Plain text, deliberately untranslated (it's a bug-report payload),
    one "Label: value" per line. Pure string assembly.
*/

.pragma library

// Build the clipboard text from a sysInfo-shaped object. Missing fields render
// as empty after the colon.
function clipboardText(info) {
    var i = info || {};
    var lines = [
        "AppGrid: " + (i.appgridVersion || ""),
        "Install: " + (i.installType || ""),
        "Variant: " + (i.variant || ""),
        "Session: " + (i.sessionType || ""),
        "Plasma: " + (i.plasmaVersion || ""),
        "KF: " + (i.kfVersion || ""),
        "Qt: " + (i.qtVersion || ""),
        "OS: " + (i.os || ""),
        "Screens: " + (i.screens || "")
    ];
    return lines.join("\n");
}
