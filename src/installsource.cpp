/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "installsource.h"

namespace InstallSource
{
QString detect(const QString &exec, const QString &entryPath, const QString &snapName)
{
    // A web app may itself run in a Flatpak browser; it is still a web app.
    if (exec.contains(QLatin1String("--app=")) || exec.contains(QLatin1String("--app-id="))) {
        return QStringLiteral("Web App");
    }
    // Whole path segments only: a name merely containing "snap" (snapper,
    // Snapshot) or "flatpak" is a system app. Not the X-Flatpak key either:
    // the distro's Podman Desktop package ships upstream's .desktop with it.
    if (entryPath.contains(QLatin1String("/flatpak/exports/")) || exec.contains(QLatin1String("flatpak run"))) {
        return QStringLiteral("Flatpak");
    }
    if (!snapName.isEmpty() || entryPath.contains(QLatin1String("/snapd/desktop/")) || exec.contains(QLatin1String("/snap/"))) {
        return QStringLiteral("Snap");
    }
    if (exec.contains(QLatin1String("appimage"), Qt::CaseInsensitive)) {
        return QStringLiteral("AppImage");
    }
    return QStringLiteral("System");
}

QString of(const KService::Ptr &service)
{
    if (!service) {
        return {};
    }
    // entryPath() is the absolute .desktop path KService resolved.
    return detect(service->exec(), service->entryPath(), service->property<QString>(QStringLiteral("X-SnapInstanceName")));
}
}
