/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>
#include <QStringList>

class KConfig;
class KConfigGroup;
#include <QString>

/**
 * Resolves the user's default applications for the search-ranking boost,
 * separated from AppFilterModel so the "which apps are the user's defaults"
 * concern — reading mimeapps.list, KApplicationTrader and kdeglobals — lives on
 * its own. Stateless: AppFilterModel owns the resulting sets (it needs fast
 * per-row lookup and a test seam), this only computes them.
 */
namespace DefaultAppsResolver
{
struct Result {
    /// Role defaults (browser/mail/file-manager via KApplicationTrader, terminal
    /// via kdeglobals) — outrank everything else in the search tiebreak.
    QSet<QString> preferred;
    /// Every app that is a mimeapps.list default for some type — a weaker boost.
    QSet<QString> defaults;
};

/** Read all sources and resolve the current default-app sets. */
[[nodiscard]] Result resolve();

// The parts of resolve(), tested on their own.

/** Desktop ids from the [Default Applications] group of a mimeapps.list
 *  file. Order is unspecified; empty on no matches. */
[[nodiscard]] QStringList mimeAppsDefaults(const KConfig &mimeApps);

/** The mimeapps.list files of the XDG mime-apps spec, most important
 *  first: in each of @p configDirs, then in "applications" under each of
 *  @p dataDirs, the "<desktop>-mimeapps.list" of each of @p desktops
 *  (XDG_CURRENT_DESKTOP, lowercased) before the plain "mimeapps.list". */
[[nodiscard]] QStringList mimeAppsListPaths(const QStringList &configDirs, const QStringList &dataDirs, const QStringList &desktops);

/** Merged default-app desktop ids from every mimeapps.list of this
 *  session (see mimeAppsListPaths). */
[[nodiscard]] QStringList loadMimeAppsDefaults();

/** Terminal-default values (TerminalApplication / TerminalService) from
 *  kdeglobals' [General] group @p general. Each value is either a
 *  .desktop id or an exec line; resolving it to a storage id is the caller's
 *  job. Empty if none. The browser default is NOT read from kdeglobals — it is
 *  resolved via KApplicationTrader (x-scheme-handler), the authoritative source
 *  System Settings uses; terminals have no mimetype, so kdeglobals is theirs. */
[[nodiscard]] QStringList kdeTerminalDefaults(const KConfigGroup &general);

/** Those terminal-default values from kdeglobals. */
[[nodiscard]] QStringList loadKdeTerminalDefaults();

/** Executable basename from an exec line: "/usr/bin/ghostty --foo" → "ghostty",
 *  "firefox.desktop" → "firefox.desktop" (no path/args). Used to match a KDE
 *  default-terminal exec back to its application. */
[[nodiscard]] QString execBinaryName(const QString &execLine);
}
