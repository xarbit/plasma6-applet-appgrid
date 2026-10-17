/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>

#include <QString>

/**
 * Where an installed app came from: "Web App", "Flatpak", "Snap", "AppImage"
 * or "System". Shown on the app and used to pick the Discover backend.
 */
namespace InstallSource
{
/** The source of the app with @p exec, installed at @p entryPath. Flatpak
 *  and snapd mark the desktop files they export with @p flatpakId
 *  (X-Flatpak) and @p snapName (X-SnapInstanceName); without them the
 *  export dirs and the exec line tell. */
[[nodiscard]] QString detect(const QString &exec, const QString &entryPath, const QString &flatpakId = {}, const QString &snapName = {});

/** detect() for @p service. */
[[nodiscard]] QString of(const KService::Ptr &service);
}
