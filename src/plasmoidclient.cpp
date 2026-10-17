/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "plasmoidclient.h"

#include "appgridconstants.h"
#include "plasmoidinterface.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

PlasmoidClient::PlasmoidClient(QObject *parent)
    : QObject(parent)
{
}

void PlasmoidClient::setInProcessPin(bool inProcess)
{
    m_inProcessPin = inProcess;
}

bool PlasmoidClient::plasmoidPresent()
{
    auto bus = QDBusConnection::sessionBus();
    return bus.interface() && bus.interface()->isServiceRegistered(AppGrid::PlasmoidDbus::Service);
}

void PlasmoidClient::addToTaskManager(const QString &desktopFile)
{
    if (desktopFile.isEmpty()) {
        return;
    }
    // Pinning (with activities) is what Kicker does in-process via the corona +
    // libtaskmanager. A live applet hosts us: hand it back to QML to run the real
    // ContainmentInterface. The standalone daemon has no corona, so it delegates
    // to the center plasmoid's D-Bus helper instead.
    if (m_inProcessPin) {
        Q_EMIT addToTaskManagerRequested(desktopFile);
        return;
    }
    PlasmoidInterface plasmoid(AppGrid::PlasmoidDbus::Service, AppGrid::PlasmoidDbus::Path, QDBusConnection::sessionBus());
    plasmoid.requestAddToTaskManager(desktopFile);
}

bool PlasmoidClient::canPinToTaskManager() const
{
    return m_inProcessPin || plasmoidPresent();
}

void PlasmoidClient::setButtonTargetId(const QString &plasmoidId)
{
    // A launcher started from a terminal / autostart / its own settings action
    // has no origin plasmoid, so it edits no button.
    const QString path = plasmoidId.isEmpty() ? QString() : AppGrid::PlasmoidDbus::pathFor(plasmoidId);
    if (m_buttonTargetPath == path) {
        return;
    }
    m_buttonTargetPath = path;
    Q_EMIT buttonTargetChanged();
}

bool PlasmoidClient::canConfigureButton() const
{
    return !m_buttonTargetPath.isEmpty() && plasmoidPresent();
}

QVariantMap PlasmoidClient::buttonAppearance() const
{
    return m_buttonAppearance;
}

void PlasmoidClient::requestButtonAppearance()
{
    if (m_buttonTargetPath.isEmpty()) {
        return;
    }
    // Asynchronous: a blocking call here would spin a nested event loop inside
    // the settings window's QML construction (deadlock-prone, can crash). Fetch
    // and notify when the reply lands instead.
    PlasmoidInterface plasmoid(AppGrid::PlasmoidDbus::Service, m_buttonTargetPath, QDBusConnection::sessionBus());
    auto *watcher = new QDBusPendingCallWatcher(plasmoid.buttonAppearance(), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        const QDBusPendingReply<QVariantMap> reply = *call;
        if (reply.isValid()) {
            m_buttonAppearance = reply.value();
            Q_EMIT buttonAppearanceChanged();
        }
        call->deleteLater();
    });
}

void PlasmoidClient::setButtonAppearance(const QVariantMap &values)
{
    PlasmoidInterface plasmoid(AppGrid::PlasmoidDbus::Service, m_buttonTargetPath, QDBusConnection::sessionBus());
    plasmoid.setButtonAppearance(values);
}
