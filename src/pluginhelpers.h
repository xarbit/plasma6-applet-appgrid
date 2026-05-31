/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

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
}
