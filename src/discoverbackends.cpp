/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "discoverbackends.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QStandardPaths>

namespace DiscoverBackends
{
QString forInstallSource(const QString &source)
{
    if (source == QLatin1String("System"))
        return QStringLiteral("packagekit");
    if (source == QLatin1String("Flatpak"))
        return QStringLiteral("flatpak");
    if (source == QLatin1String("Snap"))
        return QStringLiteral("snap");
    return {};
}

QString toolForBackend(const QString &backend)
{
    if (backend == QLatin1String("flatpak"))
        return QStringLiteral("flatpak");
    if (backend == QLatin1String("snap"))
        return QStringLiteral("snap");
    return {};
}

namespace
{
// PackageKit registers a D-Bus-activated system service; the service file is
// the reliable "installed" signal — the daemon lives in libexec and the CLI
// may be absent. Standard freedesktop location, with a source-install fallback.
bool packageKitServicePresent()
{
    static const QLatin1String bases[] = {QLatin1String("/usr/share"), QLatin1String("/usr/local/share")};
    for (const auto &base : bases) {
        if (QFileInfo::exists(base + QLatin1String("/dbus-1/system-services/org.freedesktop.PackageKit.service")))
            return true;
    }
    return false;
}
}

bool isBackendInstalled(const QString &name)
{
    const QString relPath = QStringLiteral("discover/") + name + QStringLiteral("-backend.so");
    bool pluginFound = false;
    for (const auto &dir : QCoreApplication::libraryPaths()) {
        if (QFileInfo::exists(dir + QLatin1Char('/') + relPath)) {
            pluginFound = true;
            break;
        }
    }
    if (!pluginFound)
        return false;

    if (name == QLatin1String("packagekit"))
        return packageKitServicePresent();

    const QString tool = toolForBackend(name);
    return tool.isEmpty() || !QStandardPaths::findExecutable(tool).isEmpty();
}
}
