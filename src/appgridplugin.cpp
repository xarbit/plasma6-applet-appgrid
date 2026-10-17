/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include "appgridconstants.h"
#include "appletmigration.h"
#include "plasmoidadaptor.h"
#include "plasmoidservice.h"
#include "qmltypes.h"

#include <KConfig>
#include <KConfigGroup>
#include <QDBusConnection>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

#include <PlasmaQuick/AppletQuickItem>

AppGridPlugin::AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : Plasma::Applet(parent, data, args)
{
    // The shared QML names the C++ enums; register them before it loads.
    AppGridQml::registerTypes();
    // Do NOT prune/sync this applet's config here: config() is plasmashell's
    // appletsrc, and writing+syncing it from the constructor (before the shell
    // finishes restoring its containments) persists a partial file and resets
    // panel settings. Legacy keys are harmless; leave them.

    // PlasmoidItem::init() connects activated → setExpanded(true). For custom
    // Window mode, we add a second connection (fires after PlasmoidItem's) that
    // immediately reverses the expansion, preventing the native popup from
    // showing. The popup variant sets m_useNativeActivation = true to skip this.
    QTimer::singleShot(0, this, [this]() {
        if (!m_useNativeActivation) {
            auto *quickItem = PlasmaQuick::AppletQuickItem::itemForApplet(this);
            if (quickItem) {
                // Context object is quickItem (not this): the lambda captures it
                // raw, so the connection must die with it — the applet outlives
                // the QML representation when Plasma recreates it.
                connect(this, &Plasma::Applet::activated, quickItem, [quickItem]() {
                    quickItem->setProperty("expanded", false);
                });
            }
            // Let the standalone daemon delegate its in-process Task Manager pin.
            registerPlasmoidService();
        }
    });
}

AppGridPlugin::~AppGridPlugin() = default;

void AppGridPlugin::updateButtonAppearanceCache(const QVariantMap &values)
{
    // Stored on the plugin (not the helper), so a QML push before the helper is
    // created in the deferred init still lands and the daemon reads live values.
    m_buttonAppearance = values;
}

QVariantMap AppGridPlugin::buttonAppearance() const
{
    return m_buttonAppearance;
}

void AppGridPlugin::registerPlasmoidService()
{
    m_plasmoidService = new AppGridPlasmoidService(this, this);
    // The daemon's pin request goes straight to this applet's QML, which runs the
    // real pin (no controller needed for that).
    connect(m_plasmoidService, &AppGridPlasmoidService::addToTaskManagerRequested, this, [this](const QString &desktopFile) {
        if (!desktopFile.isEmpty()) {
            Q_EMIT addToTaskManagerRequested(desktopFile);
        }
    });
    connect(m_plasmoidService, &AppGridPlasmoidService::setButtonAppearanceRequested, this, &AppGridPlugin::setButtonAppearanceRequested);

    new PlasmoidAdaptor(m_plasmoidService);
    auto bus = QDBusConnection::sessionBus();
    // Per-instance object path so the daemon can address THIS plasmoid's button
    // (icon/label) specifically when the user configures from it (#191). Each
    // instance owns a different path, so registration never collides.
    bus.registerObject(AppGrid::PlasmoidDbus::pathFor(QString::number(id())), m_plasmoidService, QDBusConnection::ExportAdaptors);
    // Also at the shared /Plasmoid path: the first instance wins it and services
    // the corona-only ops (pin, panel screen) and the no-origin settings case.
    bus.registerObject(AppGrid::PlasmoidDbus::Path, m_plasmoidService, QDBusConnection::ExportAdaptors);
    // registerService may fail if another center plasmoid already owns the name —
    // harmless: that instance services the daemon's requests.
    bus.registerService(AppGrid::PlasmoidDbus::Service);
}

AppGridController *AppGridPlugin::controller()
{
    if (!m_controller) {
        m_controller = new AppGridController(this);
        // A live applet hosts the controller, so the Task Manager pin runs
        // in-process (Kicker's ContainmentInterface needs a corona): the
        // controller emits a request this applet forwards to its QML. The
        // standalone daemon leaves this off.
        m_controller->plasmoidClient()->setInProcessPin(true);
        connect(m_controller->plasmoidClient(), &PlasmoidClient::addToTaskManagerRequested, this, &AppGridPlugin::addToTaskManagerRequested);
    }
    return m_controller;
}

QString AppGridPlugin::panelScreenName() const
{
    // containment()->screen() is the SHELL's screen index, which need not match
    // QGuiApplication::screens() order on multi-monitor — indexing Qt's list with
    // it picks the wrong output. Read the actual output from the applet's window.
    auto *item = PlasmaQuick::AppletQuickItem::itemForApplet(const_cast<AppGridPlugin *>(this));
    if (item && item->window() && item->window()->screen()) {
        return item->window()->screen()->name();
    }
    return {};
}

QVariantMap AppGridPlugin::systemInfo()
{
    return controller()->systemActions()->systemInfo(m_useNativeActivation ? QStringLiteral("Panel") : QStringLiteral("Center"));
}

void AppGridPlugin::configureStandaloneWindow()
{
    // Open straight into the settings window; --configure skips popping the launcher.
    m_standalone.triggerAsOwner(QString::number(id()), AppGrid::Dbus::MethodConfigure, {AppGrid::Standalone::FlagConfigure});
}

void AppGridPlugin::migrateConfigToStandalone()
{
    KConfig appgridrc(QStringLiteral("appgridrc"));
    AppletMigration::copySettingsToStandalone(config().group(QStringLiteral("General")), appgridrc);
}

void AppGridPlugin::migrateLaunchState()
{
    AppletMigration::moveLaunchState(config().group(QStringLiteral("General")), *controller()->launchState());
}

void AppGridPlugin::toggleStandaloneWindow()
{
    // This plasmoid owns the launcher session it opens, so the launcher's
    // Settings action edits this plasmoid's panel button (#191).
    m_standalone.triggerAsOwner(QString::number(id()), AppGrid::Dbus::MethodToggle);
}
