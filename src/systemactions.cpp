/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "systemactions.h"

#include "appgridconstants.h"
#include "applauncher.h"
#include "appmodel.h"
#include "appstreamresolver.h"
#include "discoverbackends.h"
#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KDesktopFile>
#include <KIO/CommandLauncherJob>
#include <KLocalizedString>
#include <KOSRelease>
#include <KService>
#include <KSharedConfig>
#include <KShell>
#include <KTerminalLauncherJob>
#include <KWindowSystem>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QStandardPaths>
#include <QUrl>
#include <kcoreaddons_version.h>
#include <plasma_version.h>

namespace
{
// The Discover backend (PackageKit / Flatpak / Snap) owning the installed copy
// of @p service, or empty if unknown. The installed .desktop path — not the
// AppStream id — identifies the source, since one component can ship from
// several backends.
QString discoverBackendFor(const KService::Ptr &service)
{
    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    return DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));
}

// The AppStream component id the pool resolves for @p service (keyed by its
// .desktop id), or empty when AppStream doesn't know the component.
QString appStreamIdFor(const KService::Ptr &service)
{
    return AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop"));
}

// Validate that the given shell path is listed in /etc/shells.
// Falls back to /bin/sh if empty or not found.
QString validatedShell(const QString &shell)
{
    if (shell.isEmpty()) {
        return QStringLiteral("/bin/sh");
    }

    QFile file(QStringLiteral("/etc/shells"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString contents = QString::fromUtf8(file.readAll());
        if (PluginHelpers::parseShells(contents).contains(shell)) {
            return shell;
        }
    }

    qWarning() << "AppGrid: shell not in /etc/shells, falling back to /bin/sh:" << shell;
    return QStringLiteral("/bin/sh");
}
}

SystemActions::SystemActions(QObject *parent)
    : QObject(parent)
{
}

void SystemActions::addToDesktop(const QString &desktopFile)
{
    if (desktopFile.isEmpty()) {
        return;
    }
    // The default Plasma desktop is Folder View, which shows the XDG Desktop
    // directory: drop a copy of the .desktop there (what Folder View does on an
    // app drag), marked executable so Plasma trusts it as a launcher. (Kicker
    // adds an org.kde.plasma.icon widget instead, but that resolves its .desktop
    // asynchronously and can't be driven reliably from out of process.)
    const QString desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (desktopDir.isEmpty()) {
        return;
    }
    QDir().mkpath(desktopDir);
    const QString dest = desktopDir + QLatin1Char('/') + QFileInfo(desktopFile).fileName();
    QFile::remove(dest);
    if (!QFile::copy(desktopFile, dest)) {
        return;
    }
    QFile::setPermissions(dest,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup | QFileDevice::ExeGroup
                              | QFileDevice::ReadOther | QFileDevice::ExeOther);
}

bool SystemActions::canAddToDesktop() const
{
    // A Folder View desktop is the only containment that shows the XDG Desktop
    // directory we drop into. Read the shell layout for one (live changes are
    // rare; the menu re-checks on each open).
    const KSharedConfig::Ptr cfg = KSharedConfig::openConfig(AppGrid::ShellLayout::AppletsConfig);
    const KConfigGroup containments = cfg->group(AppGrid::ShellLayout::ContainmentsGroup);
    const auto ids = containments.groupList();
    for (const QString &id : ids) {
        if (containments.group(id).readEntry(AppGrid::ShellLayout::PluginKey) == AppGrid::ShellLayout::FolderViewPlugin) {
            return true;
        }
    }
    return false;
}

void SystemActions::runInTerminal(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);

    // Wrap the command so the terminal stays open after it finishes. The
    // prompt goes in as an argument ($1), so a translation can hold any
    // character without breaking the script.
    const QString script = command + QStringLiteral("; echo; printf '%s\\n' \"$1\"; read _");
    const QString prompt = i18nc("@info shown in a terminal after a command finished", "[Press Enter to close]");
    const QString wrapped = KShell::joinArgs({sh, QStringLiteral("-c"), script, QStringLiteral("appgrid"), prompt});

    AppLauncher::start(new KTerminalLauncherJob(wrapped));
}

void SystemActions::runCommand(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);
    AppLauncher::start(new KIO::CommandLauncherJob(sh, {QStringLiteral("-c"), command}));
}

QStringList SystemActions::availableShells() const
{
    QFile file(QStringLiteral("/etc/shells"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    const QString contents = QString::fromUtf8(file.readAll());

    QStringList shells;
    const auto candidates = PluginHelpers::parseShells(contents);
    for (const QString &shell : candidates) {
        if (QFile::exists(shell)) {
            shells.append(shell);
        }
    }
    return shells;
}

bool SystemActions::isDiscoverAvailable() const
{
    return static_cast<bool>(KService::serviceByDesktopName(QStringLiteral("org.kde.discover")));
}

bool SystemActions::canManageInDiscover(const QString &storageId) const
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return false;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return false;
    }

    // Gate on the Discover backend owning the installed copy (PackageKit / Flatpak
    // / Snap) — a cheap, pool-free check off the installed .desktop path, which
    // pins the source better than the AppStream id (one component can ship from
    // several backends). The AppStream pool is NOT touched here: the id is resolved
    // only when the user actually clicks the action (openInDiscover), the way
    // Kickoff defers its pool load. So a right-click never maps the metadata.
    const QString backend = discoverBackendFor(service);
    return !backend.isEmpty() && DiscoverBackends::isBackendInstalled(backend);
}

void SystemActions::openInDiscover(const QString &storageId)
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    // X-AppStream-Component wins if the .desktop declares one; otherwise ask the
    // AppStream pool for the canonical id. resolve() loads the pool synchronously
    // on this first call (kept off every session that never opens Discover), so the
    // click resolves the exact component first try — no async race.
    KDesktopFile desktopFile(service->entryPath());
    QString appId = desktopFile.desktopGroup().readEntry("X-AppStream-Component", QString());
    if (appId.isEmpty()) {
        appId = appStreamIdFor(service);
    }

    // AppStream genuinely doesn't know this app — open Discover searching its name
    // so the action is never dead.
    if (appId.isEmpty()) {
        AppLauncher::start(new KIO::CommandLauncherJob(QStringLiteral("plasma-discover"), {QStringLiteral("--search"), service->name()}));
        return;
    }

    const QString backend = discoverBackendFor(service);

    // Target the backend that owns the installed copy so a multi-source app
    // (e.g. Flatpak + distro) opens the right version instead of Discover's
    // first match. CommandLauncherJob is KDE's launcher wrapper — carries the
    // desktop activation token + startup notification. Fall back to the bare
    // URL when the backend is unknown.
    if (!backend.isEmpty()) {
        // Discover's --backends identifies a backend by its plugin name, which
        // carries the -backend suffix (see `plasma-discover --listbackends`).
        const QString discoverBackend = backend + QStringLiteral("-backend");
        AppLauncher::start(new KIO::CommandLauncherJob(
            QStringLiteral("plasma-discover"),
            {QStringLiteral("--backends"), discoverBackend, QStringLiteral("--application"), QStringLiteral("appstream://") + appId}));
    } else {
        AppLauncher::open(QUrl(QStringLiteral("appstream://") + appId));
    }
}

QVariantList SystemActions::listDirectory(const QString &path) const
{
    return PluginHelpers::listDirectoryAt(path);
}

QVariantMap SystemActions::systemInfo(const QString &variant) const
{
    QVariantMap info;
    // APPGRID_VERSION carries the dev-suffix on local builds; metadata.json's
    // version doesn't, so prefer the bake-in to reflect the running binary.
    info[QStringLiteral("appgridVersion")] = QString::fromUtf8(APPGRID_VERSION);
    info[QStringLiteral("plasmaVersion")] = QStringLiteral(PLASMA_VERSION_STRING);
    info[QStringLiteral("kfVersion")] = QStringLiteral(KCOREADDONS_VERSION_STRING);
    info[QStringLiteral("qtVersion")] = QString::fromLatin1(qVersion());
    info[QStringLiteral("sessionType")] = KWindowSystem::isPlatformWayland() ? QStringLiteral("Wayland") : QStringLiteral("X11");
    info[QStringLiteral("variant")] = variant;
#ifdef APPGRID_UNIVERSAL_BUILD
    info[QStringLiteral("installType")] = QStringLiteral("Universal package");
#else
    info[QStringLiteral("installType")] = QStringLiteral("Distribution package");
#endif

    const QString os = KOSRelease().prettyName();
    if (!os.isEmpty()) {
        info[QStringLiteral("os")] = os;
    }

    // Screen info
    const auto screens = QGuiApplication::screens();
    QStringList screenList;
    for (auto *screen : screens) {
        auto geo = screen->geometry();
        screenList.append(QStringLiteral("%1 (%2x%3 @ %4x)").arg(screen->name()).arg(geo.width()).arg(geo.height()).arg(screen->devicePixelRatio()));
    }
    info[QStringLiteral("screens")] = screenList.join(QStringLiteral(", "));

    return info;
}
