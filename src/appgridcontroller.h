/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QRect>

#include "appfiltermodel.h"
#include "appgridfavoritesmodel.h"
#include "appmodel.h"
#include "categoryrowsmodel.h"
#include "defaultappsprovider.h"
#include "favoritesgroupedmodel.h"
#include "frecencyprovider.h"
#include "launchstatestore.h"
#include "menutreemodel.h"
#include "newappstracker.h"
#include "plasmoidclient.h"
#include "runnerservice.h"
#include "systemactions.h"
#include "unifiedsearchmodel.h"
#include "usedappsprovider.h"
#include "windowconfigurator.h"

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

class QWindow;

namespace KActivities
{
class Consumer;
}

/**
 * @brief Applet-independent core of the AppGrid launcher.
 *
 * Owns the models and wires them together (launch state, favourites, default
 * apps, frecency), launches apps and their actions, and places the daemon's
 * window. KRunner search (runner), the calls to the center plasmoid
 * (plasmoidClient) and the actions on the rest of the system (systemActions)
 * are services it owns and exposes. It carries no Plasma::Applet dependency,
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
    [[nodiscard]] bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    [[nodiscard]] UpdateChecker *updateChecker() const;
#endif

    /**
     * Layer-shell scope the next configurePanelWindow() applies. The standalone
     * executable sets a scope that KWin maps to WindowType::Normal so the window
     * open/close effect (Glide/Scale/Fade) animates it like KRunner. Must be set
     * before configurePanelWindow() is called.
     */
    void setLayerScope(const QString &scope);

    // --- Window management (the standalone daemon's own window) ---

    /** Configure @p window as the centered, content-sized panel surface that
     *  carries the theme background and blur. */
    Q_INVOKABLE void configurePanelWindow(QWindow *window);

    /** Place the panel surface on the right screen and center it vertically, in
     *  one atomic step (KRunner's model). Picks the target screen — the active
     *  output (from KWin, authoritative on Wayland) when @p useActiveScreen, else
     *  the panel's screen — sets the layer surface to it explicitly, and sets the
     *  top margin from THAT screen's height: (height - panelFullHeight)/2 plus the
     *  user vertical offset (@p verticalOffsetPercent of the slack). Doing screen
     *  + margin together from the same screen avoids the cross-screen jump a split
     *  (compositor picks screen, QML computes margin off a lagging QScreen) caused.
     *  Wayland-only. @p panelFullHeight is the full (non-compact) panel height so a
     *  compact panel still hangs from the full panel's top. */
    Q_INVOKABLE void positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen);

    /** Broadcast an app launch to the system-wide KActivities database. */
    Q_INVOKABLE void notifyAppLaunched(const QString &storageId);

    /** Enable/disable the search-time frecency bias (opt-in via ConfigSearch). */
    Q_INVOKABLE void setSearchUsesFrecency(bool enabled);

    /** Surface hidden apps in search results when @p enabled is true. */
    Q_INVOKABLE void setSearchShowsHidden(bool enabled);

    /** Opt-in per-activity scoping (favorites menus + folders). Off (default)
     *  feeds the store an empty activity so folders stay global. */
    Q_INVOKABLE void setActivityScopingEnabled(bool enabled);

    /** Returns application-defined actions (jumplist) for the given storageId. */
    [[nodiscard]] Q_INVOKABLE QVariantList appActions(const QString &storageId);

    /** Launch the app action named @p actionName (KServiceAction::name(), as
     *  returned by appActions()) of @p storageId. By name, not by index:
     *  appActions() skips actions without text, so its indices don't match
     *  KService::actions(). */
    Q_INVOKABLE void launchAppAction(const QString &storageId, const QString &actionName);

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
    // Feeds the current activity to m_launchState so folders are per-activity;
    // the store itself stays KConfig-only. Gated by m_activityScoping (opt-in):
    // off feeds an empty activity, keeping folders global.
    KActivities::Consumer *m_activities = nullptr;
    bool m_activityScoping = false;
    RunnerService m_runner;
    UnifiedSearchModel m_searchModel;
    FrecencyProvider m_frecencyProvider;
    UsedAppsProvider m_usedApps;
    // Declared after m_usedApps: the tracker subscribes to it on construction.
    NewAppsTracker m_newAppsTracker;
    // Owns the standalone launcher window's layer-shell setup + positioning; the
    // Q_INVOKABLE configure/position methods forward here.
    WindowConfigurator m_window;
    PlasmoidClient m_plasmoidClient;
    SystemActions m_systemActions;
#ifdef APPGRID_UNIVERSAL_BUILD
    mutable UpdateChecker *m_updateChecker = nullptr;
#endif
};
