/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include "appgridconstants.h"

#include <KConfig>
#include <KConfigGroup>
#include <KIO/CommandLauncherJob>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

#include <Plasma/Containment>
#include <PlasmaQuick/AppletQuickItem>

AppGridPlugin::AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : Plasma::Applet(parent, data, args)
    , m_controller(this)
{
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

AppGridPlasmoidService::AppGridPlasmoidService(AppGridPlugin *plugin, QObject *parent)
    : QObject(parent)
    , m_plugin(plugin)
{
}

void AppGridPlasmoidService::requestAddToTaskManager(const QString &desktopFile)
{
    Q_EMIT addToTaskManagerRequested(desktopFile);
}

QString AppGridPlasmoidService::panelScreenName() const
{
    return m_plugin ? m_plugin->panelScreenName() : QString();
}

QVariantMap AppGridPlasmoidService::buttonAppearance() const
{
    return m_plugin ? m_plugin->buttonAppearance() : QVariantMap();
}

void AppGridPlasmoidService::setButtonAppearance(const QVariantMap &values)
{
    Q_EMIT setButtonAppearanceRequested(values);
}

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
    connect(m_plasmoidService, &AppGridPlasmoidService::addToTaskManagerRequested, this, &AppGridPlugin::addToTaskManagerRequested);
    connect(m_plasmoidService, &AppGridPlasmoidService::setButtonAppearanceRequested, this, &AppGridPlugin::setButtonAppearanceRequested);

    auto bus = QDBusConnection::sessionBus();
    // Per-instance object path so the daemon can address THIS plasmoid's button
    // (icon/label) specifically when the user configures from it (#191). Each
    // instance owns a different path, so registration never collides.
    bus.registerObject(AppGrid::PlasmoidDbus::pathFor(QString::number(id())), m_plasmoidService, QDBusConnection::ExportScriptableContents);
    // Also at the shared /Plasmoid path: the first instance wins it and services
    // the corona-only ops (pin, panel screen) and the no-origin settings case.
    bus.registerObject(AppGrid::PlasmoidDbus::Path, m_plasmoidService, QDBusConnection::ExportScriptableContents);
    // registerService may fail if another center plasmoid already owns the name —
    // harmless: that instance services the daemon's requests.
    bus.registerService(AppGrid::PlasmoidDbus::Service);
}

// --- Property forwarders ---

AppFilterModel *AppGridPlugin::appsModel() const
{
    return m_controller.appsModel();
}

QAbstractItemModel *AppGridPlugin::runnerModel() const
{
    return m_controller.runnerModel();
}

QObject *AppGridPlugin::runnerSourceModel() const
{
    return m_controller.runnerSourceModel();
}

UnifiedSearchModel *AppGridPlugin::searchModel() const
{
    return m_controller.searchModel();
}

bool AppGridPlugin::isWayland() const
{
    return m_controller.isWayland();
}

bool AppGridPlugin::isUniversalBuild() const
{
    return m_controller.isUniversalBuild();
}

#ifdef APPGRID_UNIVERSAL_BUILD
UpdateChecker *AppGridPlugin::updateChecker() const
{
    return m_controller.updateChecker();
}
#endif

// --- Window management forwarders ---

void AppGridPlugin::configureWindow(QWindow *window)
{
    m_controller.configureWindow(window);
}

void AppGridPlugin::configurePanelWindow(QWindow *window)
{
    m_controller.configurePanelWindow(window);
}

qreal AppGridPlugin::windowDevicePixelRatio(QWindow *window) const
{
    return m_controller.windowDevicePixelRatio(window);
}

void AppGridPlugin::setInputRect(QWindow *window, int x, int y, int w, int h)
{
    m_controller.setInputRect(window, x, y, w, h);
}

void AppGridPlugin::notifyAppLaunched(const QString &storageId)
{
    m_controller.notifyAppLaunched(storageId);
}

void AppGridPlugin::addToTaskManager(const QString &desktopFile)
{
    // Run in-process: the variant's QML pins via Kicker's ContainmentInterface,
    // which needs this live applet + its corona (activities included). The
    // daemon reaches the same signal through AppGridPlasmoidService on D-Bus.
    Q_EMIT addToTaskManagerRequested(desktopFile);
}

void AppGridPlugin::addToDesktop(const QString &desktopFile)
{
    m_controller.addToDesktop(desktopFile);
}

bool AppGridPlugin::canPinToTaskManager() const
{
    // The plasmoid runs the pin in-process (it has the applet + corona).
    return true;
}

bool AppGridPlugin::canAddToDesktop() const
{
    return m_controller.canAddToDesktop();
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

void AppGridPlugin::setSearchUsesFrecency(bool enabled)
{
    m_controller.setSearchUsesFrecency(enabled);
}

void AppGridPlugin::setSearchShowsHidden(bool enabled)
{
    m_controller.setSearchShowsHidden(enabled);
}

// --- Prefix mode forwarders ---

void AppGridPlugin::runInTerminal(const QString &command, const QString &shell)
{
    m_controller.runInTerminal(command, shell);
}

void AppGridPlugin::runCommand(const QString &command, const QString &shell)
{
    m_controller.runCommand(command, shell);
}

QStringList AppGridPlugin::availableShells()
{
    return m_controller.availableShells();
}

bool AppGridPlugin::runRunnerResult(int index)
{
    return m_controller.runRunnerResult(index);
}

bool AppGridPlugin::runRunnerAction(int index, int actionIndex)
{
    return m_controller.runRunnerAction(index, actionIndex);
}

QString AppGridPlugin::runnerSubstitutionText(int index)
{
    return m_controller.runnerSubstitutionText(index);
}

QVariantList AppGridPlugin::appActions(const QString &storageId)
{
    return m_controller.appActions(storageId);
}

void AppGridPlugin::launchAppAction(const QString &storageId, int actionIndex)
{
    m_controller.launchAppAction(storageId, actionIndex);
}

bool AppGridPlugin::isDiscoverAvailable() const
{
    return m_controller.isDiscoverAvailable();
}

bool AppGridPlugin::canManageInDiscover(const QString &storageId) const
{
    return m_controller.canManageInDiscover(storageId);
}

void AppGridPlugin::openInDiscover(const QString &storageId)
{
    m_controller.openInDiscover(storageId);
}

QVariantList AppGridPlugin::listDirectory(const QString &path)
{
    return m_controller.listDirectory(path);
}

// --- System info ---

QVariantMap AppGridPlugin::systemInfo()
{
    return m_controller.systemInfo(m_useNativeActivation ? QStringLiteral("Panel") : QStringLiteral("Center"));
}

void AppGridPlugin::triggerStandalone(const QString &dbusMethod, const QStringList &launchArgs, const QVariantList &dbusArgs)
{
    auto bus = QDBusConnection::sessionBus();
    const bool running = bus.interface() && bus.interface()->isServiceRegistered(AppGrid::Dbus::Service);

    if (running) {
        // Detect a stale daemon left over from an upgrade — its build differs
        // from ours, so it lacks our D-Bus methods. Checked once and cached;
        // re-checked after a replace (so the fresh instance is re-validated).
        if (!m_daemonVersionChecked) {
            // Short timeout: this runs in plasmashell, so a hung daemon must not
            // freeze the panel. On timeout the reply is invalid → treated as not
            // stale → we just toggle it rather than aggressively replacing it.
            auto probe = QDBusMessage::createMethodCall(AppGrid::Dbus::Service, AppGrid::Dbus::Path, AppGrid::Dbus::Interface, AppGrid::Dbus::MethodVersion);
            const QDBusReply<QString> version = bus.call(probe, QDBus::Block, AppGrid::Dbus::CallTimeoutMs);
            m_daemonStale = version.isValid() && version.value() != QLatin1String(APPGRID_VERSION);
            m_daemonVersionChecked = true;
        }
        if (!m_daemonStale) {
            // Current daemon — invoke the requested method on it (with any args).
            auto call = QDBusMessage::createMethodCall(AppGrid::Dbus::Service, AppGrid::Dbus::Path, AppGrid::Dbus::Interface, dbusMethod);
            if (!dbusArgs.isEmpty()) {
                call.setArguments(dbusArgs);
            }
            bus.send(call);
            return;
        }
        // Stale: ask it to quit, then relaunch our build with --replace (it polls
        // for the freed bus name and takes over). Re-validate it next time.
        bus.send(QDBusMessage::createMethodCall(AppGrid::Dbus::Service, AppGrid::Dbus::Path, AppGrid::Dbus::Interface, AppGrid::Dbus::MethodQuit));
        m_daemonVersionChecked = false;
        QStringList args = launchArgs;
        args << AppGrid::Standalone::FlagReplace;
        auto *job = new KIO::CommandLauncherJob(AppGrid::Standalone::Executable, args, this);
        job->start();
        return;
    }

    // Not running.
#ifdef APPGRID_DBUS_ACTIVATION
    // A method call to the activatable name starts the installed build via the
    // D-Bus/systemd .service unit, then delivers the call — no explicit launch and
    // no single-instance race. The unit starts it with --daemon (it stays hidden),
    // and this queued method drives the window.
    auto call = QDBusMessage::createMethodCall(AppGrid::Dbus::Service, AppGrid::Dbus::Path, AppGrid::Dbus::Interface, dbusMethod);
    if (!dbusArgs.isEmpty()) {
        call.setArguments(dbusArgs);
    }
    bus.send(call);
#else
    // No activation unit (e.g. the relocatable universal build): launch the binary
    // with the matching flags; it registers the service and acts on them on start.
    auto *job = new KIO::CommandLauncherJob(AppGrid::Standalone::Executable, launchArgs, this);
    job->start();
#endif
}

void AppGridPlugin::triggerStandaloneAsOwner(const QString &dbusMethod, const QStringList &extraFlags)
{
    // The id reaches a running daemon as the D-Bus method arg and a cold start as
    // a launch flag, so either way it learns which plasmoid this came from.
    const QString plasmoidId = QString::number(id());
    QStringList launchArgs = extraFlags;
    launchArgs << AppGrid::Standalone::FlagPlasmoidId + plasmoidId;
    triggerStandalone(dbusMethod, launchArgs, {plasmoidId});
}

void AppGridPlugin::configureStandaloneWindow()
{
    // Open straight into the settings window; --configure skips popping the launcher.
    triggerStandaloneAsOwner(AppGrid::Dbus::MethodConfigure, {AppGrid::Standalone::FlagConfigure});
}

void AppGridPlugin::migrateConfigToStandalone()
{
    KConfig dst(QStringLiteral("appgridrc"));
    KConfigGroup marker = dst.group(QStringLiteral("Migration"));
    if (marker.readEntry("fromPlasmoid", false)) {
        return; // already migrated — the daemon owns appgridrc now
    }
    // The applet's KConfigXT values live under [Configuration][General]; copy
    // them into the daemon's appgridrc [General] (same schema, same keys).
    KConfigGroup src = config().group(QStringLiteral("General"));
    KConfigGroup dstGeneral = dst.group(QStringLiteral("General"));
    src.copyTo(&dstGeneral);
    marker.writeEntry("fromPlasmoid", true);
    dst.sync();
}

void AppGridPlugin::migrateLaunchState()
{
    // The applet's old per-applet launch lists live under [Configuration][General]
    // (the same keys, even though the schema no longer maps them). Hand them to
    // the store, which seeds only the lists it doesn't already hold.
    const KConfigGroup src = config().group(QStringLiteral("General"));
    m_controller.launchState()->migrateFrom(src.readEntry("hiddenApps", QStringList()),
                                            src.readEntry("recentApps", QStringList()),
                                            src.readEntry("knownApps", QStringList()),
                                            src.readEntry("launchCounts", QStringList()));
}

void AppGridPlugin::toggleStandaloneWindow()
{
    // This plasmoid owns the launcher session it opens, so the launcher's
    // Settings action edits this plasmoid's panel button (#191).
    triggerStandaloneAsOwner(AppGrid::Dbus::MethodToggle);
}
