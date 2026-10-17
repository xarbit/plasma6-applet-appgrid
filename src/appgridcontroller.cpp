/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridcontroller.h"

#include "appgridconstants.h"
#include "menutreesource.h"
#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KRunner/ResultsModel>
#include <PlasmaActivities/Consumer>
#include <QQuickWindow>
#include <QWindow>

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

AppGridController::AppGridController(QObject *parent)
    : QObject(parent)
    , m_newAppsTracker(&m_usedApps)
{
    m_filterModel.setSourceModel(&m_appModel);
    // Every app launch, wherever it came from, counts towards recents and the
    // launch counts.
    connect(&m_launchService, &LaunchService::appLaunched, &m_filterModel, &AppFilterModel::recordRecentLaunch);
    m_runner.setAppModel(&m_filterModel);
    m_searchModel.setAppModel(&m_filterModel);
    m_searchModel.setRunnerModel(m_runner.filterModel());

    // The FrecencyProvider stays dormant until QML opts in (the search-bias
    // toggle). When active, every refresh of the KAStats ranking forwards
    // directly into the filter model's tiebreak input.
    connect(&m_frecencyProvider, &FrecencyProvider::scoresChanged, this, [this]() {
        m_filterModel.setFrecencyScores(m_frecencyProvider.scores());
    });
    // The default apps rank search results; the provider resolves them shortly
    // after startup and again whenever they change.
    connect(&m_defaultApps, &DefaultAppsProvider::changed, this, [this]() {
        const QSet<QString> defaults = m_defaultApps.defaults();
        m_filterModel.setDefaultApps(QStringList(defaults.cbegin(), defaults.cend()));
        m_filterModel.setPreferredApps(m_defaultApps.preferred());
    });
    QQuickWindow::setDefaultAlphaBuffer(true);

    wireLaunchState();

    // One-time tidy of stale appgridrc keys older versions left behind (same
    // shared instance LaunchStateStore uses).
    KConfigGroup appgridGeneral = KSharedConfig::openConfig(QStringLiteral("appgridrc"))->group(QStringLiteral("General"));
    PluginHelpers::pruneObsoleteKeys(appgridGeneral);

    // The AppStream pool is NOT warmed here. Its metadata catalogs are large
    // (~25 MB, dominated by the Flatpak remote catalog the distro lookup leans on
    // when the OS catalog is sparse), so a session that never opens "Manage in
    // Discover" should never map them. It loads lazily on the first openInDiscover().
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
    const auto onAppListChanged = [this]() {
        const QStringList installed = m_appModel.storageIds();
        m_newAppsTracker.refresh(installed);
        // The favourites-folder grid hides a member whose app was uninstalled
        // (it would otherwise linger as a dead tile / preview icon); the installed
        // set is its "still here" test.
        m_favoritesGrouped.setKnownApps(installed);
    };
    onAppListChanged();
    connect(&m_appModel, &QAbstractItemModel::modelReset, this, onAppListChanged);

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

    // The By Category view groups the filtered apps itself, while it is shown.
    m_categoryRows.setSourceModel(&m_filterModel);

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

    // The favourites list is held in three places: the KActivities model (the
    // source of truth), the filter model (favourites-only view, search ranking)
    // and the folder layout. Push it on every change, synchronously, so a
    // folder edit right after an unfavourite already sees the shorter list.
    const auto syncFavorites = [this]() {
        const QStringList ids = m_favorites.favoriteIds();
        m_filterModel.setFavoriteApps(ids);
        m_favoritesGrouped.setFlatFavorites(ids);
    };
    connect(&m_favorites, &QAbstractItemModel::rowsInserted, this, syncFavorites);
    connect(&m_favorites, &QAbstractItemModel::rowsRemoved, this, syncFavorites);
    connect(&m_favorites, &QAbstractItemModel::rowsMoved, this, syncFavorites);
    connect(&m_favorites, &QAbstractItemModel::modelReset, this, syncFavorites);
    connect(&m_favorites, &QAbstractItemModel::layoutChanged, this, syncFavorites);
    m_favorites.initForClient(QString(AppGrid::FavoritesClientId));
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

AppGridFavoritesModel *AppGridController::favoritesModel() const
{
    return const_cast<AppGridFavoritesModel *>(&m_favorites);
}

FavoritesGroupedModel *AppGridController::favoritesGroupedModel() const
{
    return const_cast<FavoritesGroupedModel *>(&m_favoritesGrouped);
}

CategoryRowsModel *AppGridController::categoryRowsModel() const
{
    return const_cast<CategoryRowsModel *>(&m_categoryRows);
}

MenuTreeModel *AppGridController::menuTreeModel() const
{
    // Lazy: the menu tree (and its rebuild-on-KSycoca-reset subscription) only
    // come to life the first time QML reads this — i.e. when the folders feature
    // is actually used. The tree is assembled from AppModel's cached menu scan,
    // so it costs no extra KServiceGroup walk; for the default (folders off)
    // config the tree is simply never built.
    auto *self = const_cast<AppGridController *>(this);
    if (!m_menuTreeBuilt) {
        m_menuTreeBuilt = true;
        const auto rebuild = [self]() {
            self->m_menuTreeModel.setTree(MenuTreeSource::fromScan(self->m_appModel.menuFolders(), self->m_appModel.occurrences()));
        };
        rebuild();
        connect(&m_appModel, &QAbstractItemModel::modelReset, self, rebuild);
    }
    return &self->m_menuTreeModel;
}

QAbstractItemModel *AppGridController::runnerModel() const
{
    return const_cast<RunnerService &>(m_runner).filterModel();
}

QObject *AppGridController::runnerSourceModel() const
{
    return m_runner.resultsModel();
}

RunnerService *AppGridController::runner() const
{
    return const_cast<RunnerService *>(&m_runner);
}

PlasmoidClient *AppGridController::plasmoidClient() const
{
    return const_cast<PlasmoidClient *>(&m_plasmoidClient);
}

LaunchService *AppGridController::launchService() const
{
    return const_cast<LaunchService *>(&m_launchService);
}

SystemActions *AppGridController::systemActions() const
{
    return const_cast<SystemActions *>(&m_systemActions);
}

UnifiedSearchModel *AppGridController::searchModel() const
{
    return const_cast<UnifiedSearchModel *>(&m_searchModel);
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
