/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QRect>

#include "activityscope.h"
#include "appfiltermodel.h"
#include "appgridfavoritesmodel.h"
#include "appmodel.h"
#include "categoryrowsmodel.h"
#include "defaultappsprovider.h"
#include "favoritesgroupedmodel.h"
#include "frecencyprovider.h"
#include "launchservice.h"
#include "launchstatestore.h"
#include "menutreemodel.h"
#include "newappstracker.h"
#include "plasmoidclient.h"
#include "runnerservice.h"
#include "systemactions.h"
#include "unifiedsearchmodel.h"
#include "usedappsprovider.h"

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

class QWindow;

/**
 * @brief Applet-independent core of the AppGrid launcher.
 *
 * Owns the models and wires them together (launch state, favourites, default
 * apps, frecency). Launching (launchService),
 * KRunner search (runner), the calls to the center plasmoid (plasmoidClient)
 * and the actions on the rest of the system (systemActions) are services it
 * owns and exposes. It carries no Plasma::Applet dependency,
 * so it is driven both by the AppGridPlugin applet and by the standalone
 * `appgrid` executable.
 *
 * The few pieces that genuinely need the applet — the compact global shortcut
 * and the activation-inversion — stay in AppGridPlugin.
 */
class AppGridController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(AppFilterModel *appsModel READ appsModel CONSTANT)
    Q_PROPERTY(AppGridFavoritesModel *favoritesModel READ favoritesModel CONSTANT)
    Q_PROPERTY(FavoritesGroupedModel *favoritesGroupedModel READ favoritesGroupedModel CONSTANT)
    Q_PROPERTY(MenuTreeModel *menuTreeModel READ menuTreeModel CONSTANT)
    Q_PROPERTY(CategoryRowsModel *categoryRowsModel READ categoryRowsModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *runnerModel READ runnerModel CONSTANT)
    // Opaque QObject* — QML uses it only via the dynamic queryString
    // property, no static KRunner type knowledge needed across the QML/C++
    // boundary; keeps <KRunner/ResultsModel> out of this header.
    Q_PROPERTY(QObject *runnerSourceModel READ runnerSourceModel CONSTANT)
    Q_PROPERTY(UnifiedSearchModel *searchModel READ searchModel CONSTANT)
    Q_PROPERTY(RunnerService *runner READ runner CONSTANT)
    Q_PROPERTY(PlasmoidClient *plasmoidClient READ plasmoidClient CONSTANT)
    Q_PROPERTY(SystemActions *systemActions READ systemActions CONSTANT)
    Q_PROPERTY(LaunchService *launchService READ launchService CONSTANT)
    // The hidden apps, recents and launch counts (and the favourites folders).
    Q_PROPERTY(LaunchStateStore *launchState READ launchState CONSTANT)
    // Drives QML's "Check for updates" visibility + i: view "Install" row.
    Q_PROPERTY(bool isUniversalBuild READ isUniversalBuild CONSTANT)
#ifdef APPGRID_UNIVERSAL_BUILD
    Q_PROPERTY(UpdateChecker *updateChecker READ updateChecker CONSTANT)
#endif

public:
    explicit AppGridController(QObject *parent = nullptr);

    [[nodiscard]] AppFilterModel *appsModel() const;
    /** The KActivities favourites, shared with Kicker/Kickoff. */
    [[nodiscard]] AppGridFavoritesModel *favoritesModel() const;
    /** The favourites folder grouping model (issue #18), shared by both variants. */
    [[nodiscard]] FavoritesGroupedModel *favoritesGroupedModel() const;
    /** The read-only kmenuedit folder tree for the By Category view (issue #201). */
    [[nodiscard]] MenuTreeModel *menuTreeModel() const;
    /** The By Category view's header and app rows. */
    [[nodiscard]] CategoryRowsModel *categoryRowsModel() const;
    /** The shared launch-state store (appgridrc); the plasmoid uses it to seed
     *  the store from its old per-applet config on upgrade. */
    [[nodiscard]] LaunchStateStore *launchState() const;
    [[nodiscard]] QAbstractItemModel *runnerModel() const;
    [[nodiscard]] QObject *runnerSourceModel() const;
    [[nodiscard]] UnifiedSearchModel *searchModel() const;
    [[nodiscard]] RunnerService *runner() const;
    [[nodiscard]] PlasmoidClient *plasmoidClient() const;
    [[nodiscard]] SystemActions *systemActions() const;
    [[nodiscard]] LaunchService *launchService() const;
    [[nodiscard]] bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    [[nodiscard]] UpdateChecker *updateChecker() const;
#endif

    /** Enable/disable the search-time frecency bias (opt-in via ConfigSearch). */
    Q_INVOKABLE void setSearchUsesFrecency(bool enabled);

    /** Surface hidden apps in search results when @p enabled is true. */
    Q_INVOKABLE void setSearchShowsHidden(bool enabled);

    /** Opt-in per-activity scoping (favorites menus + folders). Off (default)
     *  feeds the store an empty activity so folders stay global. */
    Q_INVOKABLE void setActivityScopingEnabled(bool enabled);

private:
    // Push the store's lists into the model on load + external change, and the
    // model's own mutations (hide, launch, recents) back into the store. The
    // equality guards on both sides stop the round-trip from looping.
    void wireLaunchState();

    AppModel m_appModel;
    AppFilterModel m_filterModel;
    // Resolves the default apps off the constructor and on change only.
    DefaultAppsProvider m_defaultApps;
    LaunchStateStore m_launchState;
    FavoritesGroupedModel m_favoritesGrouped;
    AppGridFavoritesModel m_favorites;
    CategoryRowsModel m_categoryRows;
    MenuTreeModel m_menuTreeModel;
    // Built on first menuTreeModel() read (folders feature in use), not at startup.
    mutable bool m_menuTreeBuilt = false;
    // The activity the store scopes the folders to (none unless per-activity
    // favourites are on); the store itself stays KConfig-only.
    ActivityScope m_activityScope;
    RunnerService m_runner;
    UnifiedSearchModel m_searchModel;
    FrecencyProvider m_frecencyProvider;
    UsedAppsProvider m_usedApps;
    // Declared after m_usedApps: the tracker subscribes to it on construction.
    NewAppsTracker m_newAppsTracker;
    PlasmoidClient m_plasmoidClient;
    SystemActions m_systemActions;
    LaunchService m_launchService;
#ifdef APPGRID_UNIVERSAL_BUILD
    mutable UpdateChecker *m_updateChecker = nullptr;
#endif
};
