/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridstandalone.h"

#include "appgridconstants.h"

#include <QDBusConnection>
#include <QDBusMessage>

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

QString AppGridStandalone::interfaceName()
{
    return AppGrid::Dbus::Interface;
}

bool AppGridStandalone::registerService()
{
    auto bus = QDBusConnection::sessionBus();
    // Export the scriptable Show/Hide/Toggle slots before claiming the name, so
    // a client that races in right after the name lands finds the object live.
    if (!bus.registerObject(objectPath(), this, QDBusConnection::ExportScriptableSlots)) {
        return false;
    }
    return bus.registerService(serviceName());
}

bool AppGridStandalone::callToggleOnRunningInstance(const QString &plasmoidId)
{
    auto msg = QDBusMessage::createMethodCall(serviceName(), objectPath(), interfaceName(), QStringLiteral("Toggle"));
    // Carry the origin plasmoid id (empty for a terminal launch) so the running
    // daemon's settings edit that instance's button — or none.
    msg.setArguments({plasmoidId});
    // Fire-and-forget: we exit straight after, so no reply is awaited.
    return QDBusConnection::sessionBus().send(msg);
}

bool AppGridStandalone::callToggleCompactOnRunningInstance(const QString &plasmoidId)
{
    auto msg = QDBusMessage::createMethodCall(serviceName(), objectPath(), interfaceName(), QStringLiteral("ToggleCompact"));
    msg.setArguments({plasmoidId});
    return QDBusConnection::sessionBus().send(msg);
}

bool AppGridStandalone::callConfigureOnRunningInstance(const QString &plasmoidId)
{
    auto msg = QDBusMessage::createMethodCall(serviceName(), objectPath(), interfaceName(), QStringLiteral("Configure"));
    // Carry the origin plasmoid id (empty when launched from a terminal) so the
    // running daemon retargets — or clears — the button-edit binding to match.
    msg.setArguments({plasmoidId});
    return QDBusConnection::sessionBus().send(msg);
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
