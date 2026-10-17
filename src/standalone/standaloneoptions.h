/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>

/** What the `appgrid` command line asks for. */
struct StandaloneOptions {
    // --daemon: started by D-Bus/systemd activation, not an explicit user
    // trigger. Stay hidden and let the activating method call (queued by D-Bus
    // until the service name is up) drive the window.
    bool daemon = false;
    // --configure: open the settings window straight away and skip
    // auto-showing the launcher (the plasmoid's "Configure Launcher…" when we
    // were not yet running).
    bool configure = false;
    // --compact: open collapsed to the search bar (the secondary "Open in
    // Compact Mode" shortcut fired while we were not yet running).
    bool compact = false;
    // --replace: take over from a running (stale) daemon the plasmoid is
    // quitting after an upgrade.
    bool replace = false;
    // --plasmoid-id=<id>: the center plasmoid that opened the settings, so the
    // daemon edits that instance's panel button. Empty when launched directly
    // (terminal / autostart), which clears any button-edit binding.
    QString plasmoidId;

    [[nodiscard]] static StandaloneOptions parse(const QStringList &arguments);
};
