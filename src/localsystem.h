/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

/**
 * The local system the launcher's prefix modes and terminal commands reach:
 * the installed shells and the file browser's directory listing.
 */
namespace LocalSystem
{
/** Candidate shells from /etc/shells contents: trimmed, non-empty,
 *  non-comment lines. The caller verifies each path actually exists. */
[[nodiscard]] QStringList parseShells(const QString &contents);

/** Expand a leading ~ to the user's home directory. */
[[nodiscard]] QString expandTilde(const QString &path);

/** File-browser listing for @p path. Supports a partial trailing name
 *  filter (when @p path is a non-existent dir + prefix), sorts dirs-first
 *  by name, classifies dir/file icons, and caps at 200 entries. Each
 *  entry is a map: { name, path, isDir, icon }. */
[[nodiscard]] QVariantList listDirectoryAt(const QString &path);
}
