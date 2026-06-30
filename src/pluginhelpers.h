/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSharedData> // QExplicitlySharedDataPointer (KSharedConfig::Ptr)
#include <QString>
#include <QStringList>
#include <QVariantList>

class KSharedConfig;
class KConfigGroup;

/**
 * Pure, Plasma-free helpers extracted from AppGridPlugin so the parsing and
 * filesystem-enumeration glue can be unit-tested without constructing the
 * Plasma::Applet.
 */
namespace PluginHelpers
{
/** URL scheme KActivities + KAStats use for desktop-file resources.
 *  Owned here so FrecencyProvider, AppGridPlugin, and any future
 *  consumer share one spelling. */
inline constexpr QLatin1String ApplicationsUrlPrefix{"applications:"};

/** The favourite URL for a stored token payload: a bare app storage id gets the
 *  "applications:" scheme; an id that already carries a scheme (a preferred://
 *  favourite) or is a local path (a file favourite, stored bare) is returned
 *  unchanged. Mirrors favoriteid.js's toPrefixed() so the C++ grouped model and
 *  the QML helpers agree. */
[[nodiscard]] inline QString toFavoriteId(const QString &payload)
{
    const bool alreadyComplete = payload.contains(QLatin1Char(':')) || payload.startsWith(QLatin1Char('/'));
    return alreadyComplete ? payload : ApplicationsUrlPrefix + payload;
}

/** @p resource with the "applications:" scheme removed if present, else
 *  unchanged. One spelling of how the KAStats app-resource prefix is stripped,
 *  shared by the frecency and used-apps providers. */
[[nodiscard]] inline QString stripApplicationsPrefix(const QString &resource)
{
    return resource.startsWith(ApplicationsUrlPrefix) ? resource.mid(ApplicationsUrlPrefix.size()) : resource;
}

/** Candidate shells from /etc/shells contents: trimmed, non-empty,
 *  non-comment lines. The caller verifies each path actually exists. */
[[nodiscard]] QStringList parseShells(const QString &contents);

/** Unquoted PRETTY_NAME value from /etc/os-release contents, or empty. */
[[nodiscard]] QString parseOsPrettyName(const QString &contents);

/** Expand a leading ~ to the user's home directory. */
[[nodiscard]] QString expandTilde(const QString &path);

/** File-browser listing for @p path. Supports a partial trailing name
 *  filter (when @p path is a non-existent dir + prefix), sorts dirs-first
 *  by name, classifies dir/file icons, and caps at 200 entries. Each
 *  entry is a map: { name, path, isDir, icon }. */
[[nodiscard]] QVariantList listDirectoryAt(const QString &path);

/** Desktop ids from the [Default Applications] section of a mimeapps.list
 *  file's @p contents. Order is unspecified; empty on no matches. */
[[nodiscard]] QStringList parseMimeAppsDefaults(const QString &contents);

/** Merged default-app desktop ids from the user and system mimeapps.list
 *  files. Does the filesystem reads; parsing is parseMimeAppsDefaults(). */
[[nodiscard]] QStringList loadMimeAppsDefaults();

/** First .desktop local-file path from a KRunner row's "urls" role value
 *  (@p urlsData holds a QList<QUrl>), or empty. Maps a services-runner result
 *  back to its desktop file; the caller takes fileName() for the storage id. */
[[nodiscard]] QString desktopPathFromRunnerUrls(const QVariant &urlsData);

/** Storage id (the .desktop basename) for a KRunner row's "urls" role value,
 *  or empty. The fileName() of desktopPathFromRunnerUrls() — one spelling of the
 *  "runner result → app storage id" rule shared by the runner-backed models. */
[[nodiscard]] QString runnerStorageId(const QVariant &urlsData);

/** Terminal-default values (TerminalApplication / TerminalService) from the
 *  [General] section of a kdeglobals file's @p contents. Each value is either a
 *  .desktop id or an exec line; resolving it to a storage id is the caller's
 *  job. Empty if none. The browser default is NOT read from kdeglobals — it is
 *  resolved via KApplicationTrader (x-scheme-handler), the authoritative source
 *  System Settings uses; terminals have no mimetype, so kdeglobals is theirs. */
[[nodiscard]] QStringList parseKdeTerminalDefaults(const QString &contents);

/** Those terminal-default values read from the user's kdeglobals. Does the
 *  filesystem read; parsing is parseKdeTerminalDefaults(). */
[[nodiscard]] QStringList loadKdeTerminalDefaults();

/** Executable basename from an exec line: "/usr/bin/ghostty --foo" → "ghostty",
 *  "firefox.desktop" → "firefox.desktop" (no path/args). Used to match a KDE
 *  default-terminal exec back to its application. */
[[nodiscard]] QString execBinaryName(const QString &execLine);

/** Ordered favorite runner plugin IDs from a krunnerrc-shaped @p config: the
 *  [Plugins][Favorites] "plugins" entry. These are the runners KRunner pins
 *  first, in this order; AppGrid feeds them to ResultsModel::setFavoriteIds so
 *  its search results follow the same plugin arrangement the user configured
 *  (#180). Empty when unset or @p config is null. The config is passed in
 *  (rather than opened here) so this stays unit-testable against a temp file. */
[[nodiscard]] QStringList readRunnerFavorites(const QExplicitlySharedDataPointer<KSharedConfig> &config);

/** One-time tidy of @p group: drop keys older versions wrote that no current
 *  code reads — 1.x→2.0 migration flags and appearance settings removed in the
 *  2.0 window rework. Used for both appgridrc [General] and the applet's own
 *  config group. Idempotent; syncs only when something was removed. */
void pruneObsoleteKeys(KConfigGroup &group);
}
