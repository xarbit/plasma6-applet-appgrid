/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

namespace AppGrid
{
/** Application id. APPGRID_APP_ID is injected by CMake so the translation
 *  domain, the KActivities agent id, and this constant all derive from one
 *  value in CMakeLists.txt. */
inline constexpr QLatin1String ApplicationId{APPGRID_APP_ID};

/** KAStats client id of the favourites model: the ordering scope every AppGrid
 *  variant shares, so a reorder in one shows in the others. */
inline constexpr QLatin1String FavoritesClientId{"dev.xarbit.appgrid.favorites"};

/** D-Bus single-instance surface of the standalone `appgrid` daemon
 *  (src/standalone): the daemon registers/exports it, the plasmoid toggles the
 *  daemon through it. One source so the two never drift. */
namespace Dbus
{
inline constexpr QLatin1String Service{APPGRID_APP_ID};
inline constexpr QLatin1String Path{"/Standalone"};
inline constexpr QLatin1String Interface{APPGRID_APP_ID ".Standalone"};
// Timeout for the few blocking session-bus calls (the version probe; the
// launcher-open screen lookups use the shorter OpenPathTimeoutMs). The default
// is 25s — far too long for a call made from plasmashell, where an
// unresponsive peer would otherwise freeze the panel. These peers answer in
// single-digit milliseconds; on timeout each caller has a safe fallback.
inline constexpr int CallTimeoutMs = 1000;
// Timeout for the screen lookups on the launcher-open path (KWin's active
// output, the plasmoid's panel screen). They block the window from showing,
// so cap the wait well below CallTimeoutMs: both answer in under a
// millisecond normally (about 15 ms at worst measured with plasmashell
// busy), and a miss falls back to the cursor's / primary screen.
inline constexpr int OpenPathTimeoutMs = 250;
// Method names exported by AppGridStandalone — must match its Q_SCRIPTABLE slots.
inline constexpr QLatin1String MethodToggle{"Toggle"};
inline constexpr QLatin1String MethodToggleCompact{"ToggleCompact"};
inline constexpr QLatin1String MethodConfigure{"Configure"};
inline constexpr QLatin1String MethodVersion{"Version"};
inline constexpr QLatin1String MethodQuit{"Quit"};
}

/** The standalone daemon executable and the launch flags the plasmoid passes and
 *  the daemon parses. One source so the producer (AppGridPlugin) and the consumer
 *  (src/standalone/main.cpp) never drift. */
namespace Standalone
{
inline constexpr QLatin1String Executable{"appgrid"};
// The D-Bus/systemd activation entry point (see the installed .service units)
// starts the binary with this flag. It means "you are the resident daemon" — do
// not auto-show on start; wait for the activating method call (Toggle/Configure)
// that D-Bus queues and delivers once the service name is up.
inline constexpr QLatin1String FlagDaemon{"--daemon"};
inline constexpr QLatin1String FlagConfigure{"--configure"};
inline constexpr QLatin1String FlagCompact{"--compact"};
// Replace a running (stale) daemon instead of forwarding to it — used by the
// plasmoid when the running daemon's version differs from the installed build.
inline constexpr QLatin1String FlagReplace{"--replace"};
// Identifies the center plasmoid that opened the settings window, so the daemon
// edits that exact instance's panel button (icon/label) over D-Bus (#191). Cold
// launch only; a running daemon gets the id as the Configure() D-Bus argument.
inline constexpr QLatin1String FlagPlasmoidId{"--plasmoid-id="};
}

/** KWin's session D-Bus surface. Queried for the active output to place the
 *  launcher on the right screen (the same source KRunner uses). */
namespace KWinDbus
{
inline constexpr QLatin1String Service{"org.kde.KWin"};
inline constexpr QLatin1String Path{"/KWin"};
inline constexpr QLatin1String Interface{"org.kde.KWin"};
inline constexpr QLatin1String ActiveOutputName{"activeOutputName"};
}

/** D-Bus helper the center plasmoid exports so the standalone daemon can ask it
 *  to run an in-process action that needs a live Plasma::Applet + corona — which
 *  the daemon's own process lacks. Pinning to the Task Manager (with activities)
 *  goes through Kicker's ContainmentInterface, reachable only with an applet. */
namespace PlasmoidDbus
{
inline constexpr QLatin1String Service{APPGRID_APP_ID ".plasmoid"};
inline constexpr QLatin1String Path{"/Plasmoid"};
inline constexpr QLatin1String Interface{APPGRID_APP_ID ".Plasmoid"};
inline constexpr QLatin1String AddToTaskManager{"requestAddToTaskManager"};
inline constexpr QLatin1String PanelScreenName{"panelScreenName"};
// Read/write the panel button's appearance (icon + text label) so the daemon's
// settings window can edit it on the plasmoid when one is present (#191).
inline constexpr QLatin1String ButtonAppearance{"buttonAppearance"};
inline constexpr QLatin1String SetButtonAppearance{"setButtonAppearance"};
// Per-instance object path so the daemon can address one specific plasmoid's
// button. Each center plasmoid registers its service here (and shares Path).
inline QString pathFor(const QString &appletId)
{
    return Path + QLatin1String("/") + appletId;
}
}

/** Keys for reading the Plasma shell layout (which desktops/containments exist).
 *  Used to tell whether a Folder View desktop is present to show a dropped
 *  .desktop launcher. */
namespace ShellLayout
{
inline constexpr QLatin1String AppletsConfig{"plasma-org.kde.plasma.desktop-appletsrc"};
inline constexpr QLatin1String ContainmentsGroup{"Containments"};
inline constexpr QLatin1String PluginKey{"plugin"};
inline constexpr QLatin1String FolderViewPlugin{"org.kde.plasma.folder"};
}
}
