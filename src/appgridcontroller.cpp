/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridcontroller.h"

#include "appgridconstants.h"
#include "appgridfavoritesmodel.h"
#include "appstreamresolver.h"
#include "discoverbackends.h"
#include "menutreesource.h"
#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KDesktopFile>

#include <KIO/ApplicationLauncherJob>
#include <KIO/CommandLauncherJob>
#include <KIO/OpenUrlJob>
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/ResultsModel>
#include <KService>
#include <KTerminalLauncherJob>
#include <KWindowSystem>
#include <PlasmaActivities/Consumer>

#include <PlasmaActivities/ResourceInstance>

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QUrl>
#include <QWindow>
#include <kcoreaddons_version.h>
#include <plasma_version.h>

#include <mutex>

AppGridController::AppGridController(QObject *parent)
    : QObject(parent)
    , m_newAppsTracker(&m_usedApps)
{
    // Make the favourites model importable from QML (SharedFavoritesProvider).
    // Once per process — every variant and the daemon construct a controller.
    static std::once_flag favoritesTypeOnce;
    std::call_once(favoritesTypeOnce, &AppGridFavoritesModel::registerQmlType);

    m_filterModel.setSourceModel(&m_appModel);
    m_runnerModel = new KRunner::ResultsModel(this);
    m_runnerFilterModel.setSourceModel(m_runnerModel);
    m_runnerFilterModel.setAppModel(&m_filterModel);
    m_searchModel.setAppModel(&m_filterModel);
    m_searchModel.setRunnerModel(&m_runnerFilterModel);

    // Order runner results by the user's configured plugin arrangement
    // (krunnerrc [Plugins][Favorites]), the same way KRunner/Kickoff do, and
    // keep it in sync when that config changes (#180). The watcher reparses the
    // shared config before emitting, so re-reading it picks up the change.
    m_krunnerConfig = KSharedConfig::openConfig(QStringLiteral("krunnerrc"));
    applyRunnerFavorites();
    m_krunnerWatcher = KConfigWatcher::create(m_krunnerConfig);
    connect(m_krunnerWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &, const QByteArrayList &) {
        applyRunnerFavorites();
    });

    // The FrecencyProvider stays dormant until QML opts in (the search-bias
    // toggle). When active, every refresh of the KAStats ranking forwards
    // directly into the filter model's tiebreak input.
    connect(&m_frecencyProvider, &FrecencyProvider::scoresChanged, this, [this]() {
        m_filterModel.setFrecencyScores(m_frecencyProvider.scores());
    });
    QQuickWindow::setDefaultAlphaBuffer(true);

    wireLaunchState();

    // One-time tidy of stale appgridrc keys older versions left behind (same
    // shared instance LaunchStateStore uses).
    KConfigGroup appgridGeneral = KSharedConfig::openConfig(QStringLiteral("appgridrc"))->group(QStringLiteral("General"));
    PluginHelpers::pruneObsoleteKeys(appgridGeneral);

    // Warm the AppStream pool in the background now, so the first right-click
    // "Manage in Discover" check never blocks on a synchronous metadata parse.
    AppStreamResolver::warm();
}

void AppGridController::wireLaunchState()
{
    // The store is the single source of truth (appgridrc, shared by every
    // variant + the daemon). Mirror it into the model on load and whenever
    // another process/instance changes the file; mirror the model's own launch
    // bookkeeping (hide, launch counts, recents) back. The equality guards in
    // both the model's LaunchBookkeeping and the store's setters break the loop.
    const auto pull = [this]() {
        m_filterModel.setHiddenApps(m_launchState.hiddenApps());
        m_filterModel.setRecentApps(m_launchState.recentApps());
        m_filterModel.setLaunchCountsMap(m_launchState.launchCounts());
    };
    pull();
    connect(&m_launchState, &LaunchStateStore::hiddenAppsChanged, &m_filterModel, [this]() {
        m_filterModel.setHiddenApps(m_launchState.hiddenApps());
    });
    connect(&m_launchState, &LaunchStateStore::recentAppsChanged, &m_filterModel, [this]() {
        m_filterModel.setRecentApps(m_launchState.recentApps());
    });
    connect(&m_launchState, &LaunchStateStore::launchCountsChanged, &m_filterModel, [this]() {
        m_filterModel.setLaunchCountsMap(m_launchState.launchCounts());
    });

    // New-app badge: NewAppsTracker diffs the installed set against its persisted
    // baseline (Kickoff's model) and pushes the badge set to the filter. Re-run
    // the diff whenever the app list changes (KSycoca → AppModel reset); the
    // tracker also recomputes on its own when KActivities usage changes.
    const auto refreshNewApps = [this]() {
        m_newAppsTracker.refresh(m_appModel.storageIds());
    };
    refreshNewApps();
    connect(&m_appModel, &QAbstractItemModel::modelReset, this, refreshNewApps);

    // The kmenuedit folder tree (issue #201) is built lazily — see menuTreeModel()
    // — so the default config (folders off) never pays the KServiceGroup walk on
    // every KSycoca reset.
    m_filterModel.setNewApps(m_newAppsTracker.newApps());
    connect(&m_newAppsTracker, &NewAppsTracker::newAppsChanged, &m_filterModel, [this]() {
        m_filterModel.setNewApps(m_newAppsTracker.newApps());
    });

    connect(&m_filterModel, &AppFilterModel::hiddenAppsChanged, &m_launchState, [this]() {
        m_launchState.setHiddenApps(m_filterModel.hiddenApps());
    });
    connect(&m_filterModel, &AppFilterModel::recentAppsChanged, &m_launchState, [this]() {
        m_launchState.setRecentApps(m_filterModel.recentApps());
    });
    connect(&m_filterModel, &AppFilterModel::launchCountsChanged, &m_launchState, [this]() {
        m_launchState.setLaunchCounts(m_filterModel.launchCountsMap());
    });

    // Per-activity folders: feed the current activity to the store before the
    // initial push below, and re-scope on every switch. The store re-reads that
    // activity's layout (or the shared one until it diverges) and emits the
    // folders/layout-changed signals the grouped-model wiring below already handles.
    m_activities = new KActivities::Consumer(this);
    // A just-constructed Consumer has NOT synced with the activity manager yet:
    // activities()/currentActivity() return bootstrap values (empty or the null
    // UUID), not the real state. Acting on those would prune the current
    // activity's [Folders] group (wiping its favourites order) and scope to the
    // wrong activity. So apply the initial state only once the service is Running;
    // the *Changed signals then carry real data on every later switch.
    const auto applyActivityState = [this]() {
        m_launchState.setActivity(m_activityScoping ? m_activities->currentActivity() : QString());
        // Drop per-activity folder layouts for activities removed in Plasma.
        m_launchState.pruneActivities(m_activities->activities());
    };
    if (m_activities->serviceStatus() == KActivities::Consumer::Running) {
        applyActivityState();
    }
    connect(m_activities, &KActivities::Consumer::serviceStatusChanged, &m_launchState, [applyActivityState](KActivities::Consumer::ServiceStatus status) {
        if (status == KActivities::Consumer::Running) {
            applyActivityState();
        }
    });
    connect(m_activities, &KActivities::Consumer::currentActivityChanged, &m_launchState, [this](const QString &id) {
        m_launchState.setActivity(m_activityScoping ? id : QString());
    });
    connect(m_activities, &KActivities::Consumer::activitiesChanged, &m_launchState, [this](const QStringList &activities) {
        m_launchState.pruneActivities(activities);
    });

    // Favourites folders (issue #18): the store owns the persisted definitions +
    // layout, the grouped model owns the live reconciled view. Store → model is a
    // plain read (incoming external changes update the view). Model → store writes
    // ONLY on the model's persist signals, which fire for local user actions — not
    // when the model reconciled an incoming change. That stops a process that's
    // merely reading another instance's update from echoing it back and clobbering
    // a member another instance just added.
    m_favoritesGrouped.setFavoriteFolders(m_launchState.favoriteFolders());
    m_favoritesGrouped.setFavoriteLayout(m_launchState.favoriteLayout());
    connect(&m_launchState, &LaunchStateStore::favoriteFoldersChanged, &m_favoritesGrouped, [this]() {
        m_favoritesGrouped.setFavoriteFolders(m_launchState.favoriteFolders());
    });
    connect(&m_launchState, &LaunchStateStore::favoriteLayoutChanged, &m_favoritesGrouped, [this]() {
        m_favoritesGrouped.setFavoriteLayout(m_launchState.favoriteLayout());
    });
    connect(&m_favoritesGrouped, &FavoritesGroupedModel::foldersPersistRequested, &m_launchState, [this]() {
        m_launchState.setFavoriteFolders(m_favoritesGrouped.favoriteFolders());
    });
    connect(&m_favoritesGrouped, &FavoritesGroupedModel::layoutPersistRequested, &m_launchState, [this]() {
        m_launchState.setFavoriteLayout(m_favoritesGrouped.favoriteLayout());
    });
}

LaunchStateStore *AppGridController::launchState() const
{
    return const_cast<LaunchStateStore *>(&m_launchState);
}

void AppGridController::setLayerScope(const QString &scope)
{
    m_window.setLayerScope(scope);
}

void AppGridController::configurePanelWindow(QWindow *window)
{
    m_window.configurePanelWindow(window);
}

void AppGridController::positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen)
{
    m_window.positionPanelWindow(window, panelFullHeight, verticalOffsetPercent, useActiveScreen);
}

AppFilterModel *AppGridController::appsModel() const
{
    return const_cast<AppFilterModel *>(&m_filterModel);
}

FavoritesGroupedModel *AppGridController::favoritesGroupedModel() const
{
    return const_cast<FavoritesGroupedModel *>(&m_favoritesGrouped);
}

MenuTreeModel *AppGridController::menuTreeModel() const
{
    // Lazy: the menu tree (and its rebuild-on-KSycoca-reset subscription) only
    // come to life the first time QML reads this — i.e. when the folders feature
    // is actually used. The walk never runs for the default (folders off) config.
    auto *self = const_cast<AppGridController *>(this);
    if (!m_menuTreeBuilt) {
        m_menuTreeBuilt = true;
        const auto rebuild = [self]() {
            self->m_menuTreeModel.setTree(MenuTreeSource::fromKServiceGroup());
        };
        rebuild();
        connect(&m_appModel, &QAbstractItemModel::modelReset, self, rebuild);
    }
    return &self->m_menuTreeModel;
}

QAbstractItemModel *AppGridController::runnerModel() const
{
    return const_cast<RunnerFilterModel *>(&m_runnerFilterModel);
}

QObject *AppGridController::runnerSourceModel() const
{
    return m_runnerModel;
}

void AppGridController::applyRunnerFavorites()
{
    if (m_runnerModel) {
        m_runnerModel->setFavoriteIds(PluginHelpers::readRunnerFavorites(m_krunnerConfig));
    }
}

UnifiedSearchModel *AppGridController::searchModel() const
{
    return const_cast<UnifiedSearchModel *>(&m_searchModel);
}

bool AppGridController::isWayland() const
{
    return KWindowSystem::isPlatformWayland();
}

bool AppGridController::isUniversalBuild() const
{
#ifdef APPGRID_UNIVERSAL_BUILD
    return true;
#else
    return false;
#endif
}

#ifdef APPGRID_UNIVERSAL_BUILD
UpdateChecker *AppGridController::updateChecker() const
{
    if (!m_updateChecker) {
        const QString version = QString::fromUtf8(APPGRID_VERSION);
        m_updateChecker = new UpdateChecker(version, const_cast<AppGridController *>(this));
    }
    return m_updateChecker;
}
#endif

QModelIndex AppGridController::runnerSourceIndex(int proxyIndex) const
{
    if (!m_runnerModel || proxyIndex < 0 || proxyIndex >= m_runnerFilterModel.rowCount()) {
        return {};
    }
    return m_runnerFilterModel.mapToSource(m_runnerFilterModel.index(proxyIndex, 0));
}

bool AppGridController::runRunnerResult(int index)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->run(sourceIdx);
}

bool AppGridController::runRunnerAction(int index, int actionIndex)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->runAction(sourceIdx, actionIndex);
}

QString AppGridController::runnerSubstitutionText(int index)
{
    const auto sourceIdx = runnerSourceIndex(index);
    if (!sourceIdx.isValid()) {
        return {};
    }
    // calculator is the only KRunner plugin where "keep iterating the
    // expression" beats "run and close". Extend the list as other in-place
    // runners earn their place.
    const auto match = m_runnerModel->getQueryMatch(sourceIdx);
    if (!match.runner() || match.runner()->id() != QLatin1String("calculator")) {
        return {};
    }
    return match.text();
}

QString AppGridController::runnerResultFavoriteId(int index) const
{
    const auto sourceIdx = runnerSourceIndex(index);
    if (!sourceIdx.isValid()) {
        return {};
    }
    const auto match = m_runnerModel->getQueryMatch(sourceIdx);

    // The services runner puts the canonical id in data(): "applications:<id>" for
    // an app, "applications:<id>?action=<name>" for a jump-list action. Favourite
    // it directly — for an action the query rides along, and the model stores it
    // verbatim instead of collapsing it to the bare app the way Kicker does (#64).
    const QUrl dataUrl = match.data().toUrl();
    if (dataUrl.scheme() == QLatin1String("applications")) {
        return dataUrl.toString();
    }

    // Other runners: a local file/image result (baloo, places). A .desktop URL is
    // an app (the data() path above, or the app model), not a document; remote
    // URLs aren't wired through the UI.
    for (const QUrl &url : match.urls()) {
        if (url.isLocalFile() && !url.path().endsWith(QLatin1String(".desktop"))) {
            return url.toString();
        }
    }
    return {};
}

void AppGridController::notifyAppLaunched(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    // Standard convention used by Kicker, Kickoff and friends: the resource
    // URL is "applications:<storage-id>", tagged with our agent so other
    // tools can attribute the launch to AppGrid.
    KActivities::ResourceInstance::notifyAccessed(QUrl(PluginHelpers::ApplicationsUrlPrefix + storageId), QString(AppGrid::ApplicationId));
}

void AppGridController::setInProcessTaskManagerPin(bool inProcess)
{
    m_inProcessTaskManagerPin = inProcess;
}

void AppGridController::addToTaskManager(const QString &desktopFile)
{
    if (desktopFile.isEmpty()) {
        return;
    }
    // Pinning (with activities) is what Kicker does in-process via the corona +
    // libtaskmanager. A live applet hosts us: hand it back to QML to run the real
    // ContainmentInterface. The standalone daemon has no corona, so it delegates
    // to the center plasmoid's D-Bus helper instead.
    if (m_inProcessTaskManagerPin) {
        Q_EMIT addToTaskManagerRequested(desktopFile);
        return;
    }
    auto msg = QDBusMessage::createMethodCall(AppGrid::PlasmoidDbus::Service,
                                              AppGrid::PlasmoidDbus::Path,
                                              AppGrid::PlasmoidDbus::Interface,
                                              AppGrid::PlasmoidDbus::AddToTaskManager);
    msg << desktopFile;
    QDBusConnection::sessionBus().asyncCall(msg);
}

void AppGridController::addToDesktop(const QString &desktopFile)
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

bool AppGridController::plasmoidServicePresent() const
{
    auto bus = QDBusConnection::sessionBus();
    return bus.interface() && bus.interface()->isServiceRegistered(AppGrid::PlasmoidDbus::Service);
}

bool AppGridController::canPinToTaskManager() const
{
    // In-process (applet host) can always pin; the daemon needs the center
    // plasmoid's D-Bus helper up.
    return m_inProcessTaskManagerPin || plasmoidServicePresent();
}

bool AppGridController::canConfigureButton() const
{
    // Only when the settings window was opened from a specific center plasmoid's
    // "Configure Launcher" (an explicit target was set) AND that plasmoid is on
    // the bus. A launcher started from a terminal / autostart / the in-launcher
    // settings action has no origin plasmoid, so it edits no button.
    return !m_buttonTargetPath.isEmpty() && plasmoidServicePresent();
}

void AppGridController::setButtonTargetId(const QString &plasmoidId)
{
    // The settings window edits this specific center plasmoid's button. Empty id
    // (no origin plasmoid — terminal / autostart / the launcher's own settings
    // action) → no target, so the button rows stay hidden.
    const QString path = plasmoidId.isEmpty() ? QString() : AppGrid::PlasmoidDbus::pathFor(plasmoidId);
    if (m_buttonTargetPath == path) {
        return;
    }
    m_buttonTargetPath = path;
    Q_EMIT buttonTargetChanged();
}

QVariantMap AppGridController::plasmoidButtonAppearance() const
{
    return m_lastButtonAppearance;
}

void AppGridController::requestPlasmoidButtonAppearance()
{
    if (m_buttonTargetPath.isEmpty()) {
        return;
    }
    // Asynchronous: a blocking call here would spin a nested event loop inside
    // the settings window's QML construction (deadlock-prone, can crash). Fetch
    // and notify when the reply lands instead.
    auto msg = QDBusMessage::createMethodCall(AppGrid::PlasmoidDbus::Service,
                                              m_buttonTargetPath,
                                              AppGrid::PlasmoidDbus::Interface,
                                              AppGrid::PlasmoidDbus::ButtonAppearance);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        const QDBusPendingReply<QVariantMap> reply = *call;
        if (reply.isValid()) {
            m_lastButtonAppearance = reply.value();
            Q_EMIT plasmoidButtonAppearanceChanged();
        }
        call->deleteLater();
    });
}

void AppGridController::setPlasmoidButtonAppearance(const QVariantMap &values)
{
    auto msg = QDBusMessage::createMethodCall(AppGrid::PlasmoidDbus::Service,
                                              m_buttonTargetPath,
                                              AppGrid::PlasmoidDbus::Interface,
                                              AppGrid::PlasmoidDbus::SetButtonAppearance);
    msg.setArguments({values});
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

bool AppGridController::canAddToDesktop() const
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

void AppGridController::setSearchUsesFrecency(bool enabled)
{
    // Order matters: flip the filter model's usage flag first, then drive the
    // provider. On enable, the flag is already true when the provider's first
    // scoresChanged arrives → one invalidate. On disable, the flag is already
    // false when the provider's teardown clears its scores → no spurious
    // invalidate from the cleared hash.
    m_filterModel.setSearchUsesFrecency(enabled);
    m_frecencyProvider.setEnabled(enabled);
}

void AppGridController::setSearchShowsHidden(bool enabled)
{
    m_filterModel.setSearchShowsHidden(enabled);
}

void AppGridController::setActivityScopingEnabled(bool enabled)
{
    if (m_activityScoping == enabled) {
        return;
    }
    m_activityScoping = enabled;
    // Re-scope the store: the current activity when on, empty (global) when off.
    m_launchState.setActivity(enabled ? m_activities->currentActivity() : QString());
}

// --- Prefix mode commands ---

// Validate that the given shell path is listed in /etc/shells.
// Falls back to /bin/sh if empty or not found.
static QString validatedShell(const QString &shell)
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

void AppGridController::runInTerminal(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);

    // Wrap command so the terminal stays open after it finishes.
    const QString wrapped = QStringLiteral("%1 -c '%2; echo; echo \"[Press Enter to close]\"; read _'")
                                .arg(sh, QString(command).replace(QLatin1Char('\''), QStringLiteral("'\"'\"'")));

    auto *job = new KTerminalLauncherJob(wrapped);
    job->start();
}

void AppGridController::runCommand(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);
    QProcess::startDetached(sh, {QStringLiteral("-c"), command});
}

QStringList AppGridController::availableShells()
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

QVariantList AppGridController::appActions(const QString &storageId)
{
    QVariantList result;
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return result;
    }

    const auto actions = service->actions();
    for (const auto &action : actions) {
        if (action.text().isEmpty()) {
            continue;
        }
        QVariantMap map;
        map[QStringLiteral("text")] = action.text();
        map[QStringLiteral("icon")] = action.icon();
        map[QStringLiteral("name")] = action.name();
        result.append(map);
    }
    return result;
}

void AppGridController::launchAppAction(const QString &storageId, int actionIndex)
{
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    const auto actions = service->actions();
    if (actionIndex < 0 || actionIndex >= actions.size()) {
        return;
    }

    auto *job = new KIO::ApplicationLauncherJob(actions.at(actionIndex));
    job->start();
}

bool AppGridController::isDiscoverAvailable() const
{
    return static_cast<bool>(KService::serviceByDesktopName(QStringLiteral("org.kde.discover")));
}

bool AppGridController::canManageInDiscover(const QString &storageId) const
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return false;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return false;
    }

    // The .desktop we would launch from is the installed copy, so its location
    // authoritatively identifies the backend (PackageKit / Flatpak / Snap) —
    // more reliable than the AppStream id, which on its own can't tell apart
    // multiple sources of the same component.
    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    const QString backend = DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));
    if (backend.isEmpty() || !DiscoverBackends::isBackendInstalled(backend)) {
        return false;
    }

    // Only offer the menu when AppStream actually knows the component, so we
    // never open Discover on a dead appstream:// id.
    return !AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop")).isEmpty();
}

void AppGridController::openInDiscover(const QString &storageId)
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    // X-AppStream-Component wins if the .desktop declares one; otherwise ask the
    // AppStream pool for the canonical id.
    KDesktopFile desktopFile(service->entryPath());
    QString appId = desktopFile.desktopGroup().readEntry("X-AppStream-Component", QString());
    if (appId.isEmpty()) {
        appId = AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop"));
    }
    if (appId.isEmpty()) {
        return;
    }

    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    const QString backend = DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));

    // Target the backend that owns the installed copy so a multi-source app
    // (e.g. Flatpak + distro) opens the right version instead of Discover's
    // first match. CommandLauncherJob is KDE's launcher wrapper — carries the
    // desktop activation token + startup notification. Fall back to the bare
    // URL when the backend is unknown.
    if (!backend.isEmpty()) {
        // Discover's --backends identifies a backend by its plugin name, which
        // carries the -backend suffix (see `plasma-discover --listbackends`).
        const QString discoverBackend = backend + QStringLiteral("-backend");
        auto *job = new KIO::CommandLauncherJob(
            QStringLiteral("plasma-discover"),
            {QStringLiteral("--backends"), discoverBackend, QStringLiteral("--application"), QStringLiteral("appstream://") + appId});
        job->start();
    } else {
        auto *job = new KIO::OpenUrlJob(QUrl(QStringLiteral("appstream://") + appId));
        job->start();
    }
}

QVariantList AppGridController::listDirectory(const QString &path)
{
    return PluginHelpers::listDirectoryAt(path);
}

// --- System info ---

QVariantMap AppGridController::systemInfo(const QString &variant)
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
    // isUniversalBuild() is a compile-time #ifdef constant, so it reads as a
    // known condition per build — expected, not a dead branch.
    // cppcheck-suppress knownConditionTrueFalse
    info[QStringLiteral("installType")] = isUniversalBuild() ? QStringLiteral("Universal package") : QStringLiteral("Distribution package");

    // OS info from /etc/os-release
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (osRelease.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString pretty = PluginHelpers::parseOsPrettyName(QString::fromUtf8(osRelease.readAll()));
        if (!pretty.isEmpty()) {
            info[QStringLiteral("os")] = pretty;
        }
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
