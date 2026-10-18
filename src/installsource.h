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
/** The source of the app with @p exec, installed at @p entryPath. snapd
 *  marks the desktop files it exports with @p snapName (X-SnapInstanceName);
 *  otherwise the export dirs and the exec line tell. Flatpak's X-Flatpak key
 *  is no proof: distro packages ship upstream's .desktop file with it. */
[[nodiscard]] QString detect(const QString &exec, const QString &entryPath, const QString &snapName = {});

/** detect() for @p service. */
[[nodiscard]] QString of(const KService::Ptr &service);
}
