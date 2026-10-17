/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "standaloneclient.h"

#include "appgridconstants.h"
#include "applauncher.h"
#include "standaloneinterface.h"

#include <KIO/CommandLauncherJob>
#include <QDBusConnection>
#include <QDBusConnectionInterface>

void StandaloneClient::trigger(const QString &dbusMethod, const QStringList &launchArgs, const QVariantList &dbusArgs)
{
    auto bus = QDBusConnection::sessionBus();
    const bool running = bus.interface() && bus.interface()->isServiceRegistered(AppGrid::Dbus::Service);
    StandaloneInterface daemon(AppGrid::Dbus::Service, AppGrid::Dbus::Path, bus);

    if (running) {
        // Detect a stale daemon left over from an upgrade — its build differs
        // from ours, so it lacks our D-Bus methods. Checked once and cached;
        // re-checked after a replace (so the fresh instance is re-validated).
        if (!m_versionChecked) {
            // Short timeout: this runs in plasmashell, so a hung daemon must not
            // freeze the panel. On timeout the reply is invalid → treated as not
            // stale → we just toggle it rather than aggressively replacing it.
            daemon.setTimeout(AppGrid::Dbus::CallTimeoutMs);
            QDBusPendingReply<QString> version = daemon.Version();
            version.waitForFinished();
            m_stale = version.isValid() && version.value() != QLatin1String(APPGRID_VERSION);
            m_versionChecked = true;
        }
        if (!m_stale) {
            // Current daemon — invoke the requested method on it (with any args).
            daemon.asyncCallWithArgumentList(dbusMethod, dbusArgs);
            return;
        }
        // Stale: ask it to quit, then relaunch our build with --replace (it polls
        // for the freed bus name and takes over). Re-validate it next time.
        daemon.Quit();
        m_versionChecked = false;
        QStringList args = launchArgs;
        args << AppGrid::Standalone::FlagReplace;
        AppLauncher::start(new KIO::CommandLauncherJob(AppGrid::Standalone::Executable, args));
        return;
    }

    // Not running.
#ifdef APPGRID_DBUS_ACTIVATION
    // A method call to the activatable name starts the installed build via the
    // D-Bus/systemd .service unit, then delivers the call — no explicit launch and
    // no single-instance race. The unit starts it with --daemon (it stays hidden),
    // and this queued method drives the window.
    daemon.asyncCallWithArgumentList(dbusMethod, dbusArgs);
#else
    // No activation unit (e.g. the relocatable universal build): launch the binary
    // with the matching flags; it registers the service and acts on them on start.
    AppLauncher::start(new KIO::CommandLauncherJob(AppGrid::Standalone::Executable, launchArgs));
#endif
}

QStringList StandaloneClient::ownerLaunchArgs(const QString &plasmoidId, const QStringList &extraFlags)
{
    QStringList args = extraFlags;
    args << AppGrid::Standalone::FlagPlasmoidId + plasmoidId;
    return args;
}

void StandaloneClient::triggerAsOwner(const QString &plasmoidId, const QString &dbusMethod, const QStringList &extraFlags)
{
    // The id reaches a running daemon as the D-Bus method arg and a cold start as
    // a launch flag, so either way it learns which plasmoid this came from.
    trigger(dbusMethod, ownerLaunchArgs(plasmoidId, extraFlags), {plasmoidId});
}
