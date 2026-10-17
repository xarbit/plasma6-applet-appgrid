/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridstandalone.h"

#include "appgridconstants.h"
#include "standaloneadaptor.h"
#include "standaloneinterface.h"

#include <QDBusConnection>

AppGridStandalone::AppGridStandalone(QObject *parent)
    : QObject(parent)
{
}

QString AppGridStandalone::serviceName()
{
    return AppGrid::Dbus::Service;
}

QString AppGridStandalone::objectPath()
{
    return AppGrid::Dbus::Path;
}

bool AppGridStandalone::registerService()
{
    auto bus = QDBusConnection::sessionBus();
    // Export the interface before claiming the name, so a client that races in
    // right after the name lands finds the object live.
    new StandaloneAdaptor(this);
    if (!bus.registerObject(objectPath(), this, QDBusConnection::ExportAdaptors)) {
        return false;
    }
    return bus.registerService(serviceName());
}

// These run in a second appgrid process that exits straight after, so they
// send without waiting for a reply. The origin plasmoid id (empty for a
// terminal launch) tells the running daemon whose button its settings edit.
bool AppGridStandalone::callToggleOnRunningInstance(const QString &plasmoidId)
{
    StandaloneInterface daemon(serviceName(), objectPath(), QDBusConnection::sessionBus());
    return !daemon.Toggle(plasmoidId).isError();
}

bool AppGridStandalone::callToggleCompactOnRunningInstance(const QString &plasmoidId)
{
    StandaloneInterface daemon(serviceName(), objectPath(), QDBusConnection::sessionBus());
    return !daemon.ToggleCompact(plasmoidId).isError();
}

bool AppGridStandalone::callConfigureOnRunningInstance(const QString &plasmoidId)
{
    StandaloneInterface daemon(serviceName(), objectPath(), QDBusConnection::sessionBus());
    return !daemon.Configure(plasmoidId).isError();
}

void AppGridStandalone::Show()
{
    Q_EMIT showRequested();
}

void AppGridStandalone::Hide()
{
    Q_EMIT hideRequested();
}

void AppGridStandalone::Toggle(const QString &plasmoidId)
{
    Q_EMIT toggleRequested(plasmoidId);
}

void AppGridStandalone::ToggleCompact(const QString &plasmoidId)
{
    Q_EMIT toggleCompactRequested(plasmoidId);
}

void AppGridStandalone::Configure(const QString &plasmoidId)
{
    Q_EMIT configureRequested(plasmoidId);
}

void AppGridStandalone::openSettings()
{
    Q_EMIT openSettingsRequested();
}

QString AppGridStandalone::Version() const
{
    return QStringLiteral(APPGRID_VERSION);
}

void AppGridStandalone::Quit()
{
    Q_EMIT quitRequested();
}
