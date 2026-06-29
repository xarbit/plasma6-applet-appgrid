/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>
#include <QObject>
#include <QRect>

namespace KRunner
{
class ResultsModel;
}

#include "appfiltermodel.h"
#include "appmodel.h"
#include "favoritesgroupedmodel.h"
#include "frecencyprovider.h"
#include "launchstatestore.h"
#include "menutreemodel.h"
#include "newappstracker.h"
#include "runnerfiltermodel.h"
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
 * Owns the models and all of the self-contained launcher logic (window
 * configuration, blur/shadow effects, app launch, runner, search toggles,
 * Discover integration, directory listing, system info). It carries no
 * Plasma::Applet dependency, so it can be driven both by the AppGridPlugin
 * applet (which forwards to it) and by the standalone `appgrid` executable.
 *
 * The few pieces that genuinely need the applet — the compact global shortcut
 * and the activation-inversion — stay in AppGridPlugin.
 */
class AppGridController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(AppFilterModel *appsModel READ appsModel CONSTANT)
    Q_PROPERTY(FavoritesGroupedModel *favoritesGroupedModel READ favoritesGroupedModel CONSTANT)
    Q_PROPERTY(MenuTreeModel *menuTreeModel READ menuTreeModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *runnerModel READ runnerModel CONSTANT)
    // Opaque QObject* — QML uses it only via the dynamic queryString
    // property, no static KRunner type knowledge needed across the QML/C++
    // boundary; keeps <KRunner/ResultsModel> out of this header.
    Q_PROPERTY(QObject *runnerSourceModel READ runnerSourceModel CONSTANT)
    Q_PROPERTY(UnifiedSearchModel *searchModel READ searchModel CONSTANT)
    Q_PROPERTY(bool isWayland READ isWayland CONSTANT)
    // Drives QML's "Check for updates" visibility + i: view "Install" row.
    Q_PROPERTY(bool isUniversalBuild READ isUniversalBuild CONSTANT)
#ifdef APPGRID_UNIVERSAL_BUILD
    Q_PROPERTY(UpdateChecker *updateChecker READ updateChecker CONSTANT)
#endif

public:
    explicit AppGridController(QObject *parent = nullptr);

    [[nodiscard]] AppFilterModel *appsModel() const;
    /** The favourites folder grouping model (issue #18), shared by both variants. */
    [[nodiscard]] FavoritesGroupedModel *favoritesGroupedModel() const;
    /** The read-only kmenuedit folder tree for the By Category view (issue #201). */
    [[nodiscard]] MenuTreeModel *menuTreeModel() const;
    /** The shared launch-state store (appgridrc); the plasmoid uses it to seed
     *  the store from its old per-applet config on upgrade. */
    [[nodiscard]] LaunchStateStore *launchState() const;
    [[nodiscard]] QAbstractItemModel *runnerModel() const;
    [[nodiscard]] QObject *runnerSourceModel() const;
    [[nodiscard]] UnifiedSearchModel *searchModel() const;
    [[nodiscard]] bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    [[nodiscard]] UpdateChecker *updateChecker() const;
#endif
    [[nodiscard]] bool isWayland() const;

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

    /** Pin @p desktopFile (an absolute .desktop path) to the Task Manager. When
     *  hosted by a live applet (setInProcessTaskManagerPin(true)) this just emits
     *  addToTaskManagerRequested for the applet's QML to run Kicker's in-process
     *  pin; the standalone daemon (no corona) delegates to the center plasmoid's
     *  D-Bus helper instead. */
    Q_INVOKABLE void addToTaskManager(const QString &desktopFile);

    /** Mark this controller as hosted by a live applet, so the Task Manager pin
     *  runs in-process (via addToTaskManagerRequested) rather than over D-Bus.
     *  Off by default — the standalone daemon delegates. */
    void setInProcessTaskManagerPin(bool inProcess);

    /** Add @p desktopFile (an absolute .desktop path) to the desktop by dropping
     *  it into the XDG Desktop directory (shown by Folder View). */
    Q_INVOKABLE void addToDesktop(const QString &desktopFile);

    /** True if pinning is possible — in-process when an applet hosts us, else the
     *  center plasmoid's D-Bus helper must be up. The menu hides the action when
     *  neither holds. */
    [[nodiscard]] Q_INVOKABLE bool canPinToTaskManager() const;

    /** True if a Folder View desktop exists to actually show a dropped .desktop
     *  (the menu hides "Add to Desktop" otherwise). */
    [[nodiscard]] Q_INVOKABLE bool canAddToDesktop() const;

    /** Whether a center plasmoid is present to apply the panel button's icon +
     *  label. The daemon edits those over D-Bus; false when the launcher runs
     *  standalone (no panel button), so the settings window hides those rows. */
    [[nodiscard]] Q_INVOKABLE bool canConfigureButton() const;
    /** The plasmoid's panel-button appearance as last fetched (icon/
     *  customButtonImage/useCustomButtonImage/menuLabel). Async — call
     *  requestPlasmoidButtonAppearance() to refresh, then read on the changed signal. */
    [[nodiscard]] Q_INVOKABLE QVariantMap plasmoidButtonAppearance() const;
    /** Fetch the target plasmoid's button appearance asynchronously; emits
     *  plasmoidButtonAppearanceChanged() when it arrives. */
    Q_INVOKABLE void requestPlasmoidButtonAppearance();
    /** Apply a new panel-button appearance on the plasmoid, over D-Bus. */
    Q_INVOKABLE void setPlasmoidButtonAppearance(const QVariantMap &values);

    /** Target the center plasmoid @p plasmoidId for the button get/set above (its
     *  unique D-Bus object path). Empty → the shared owner path. Set from the
     *  Configure() id when the settings window opens from a specific plasmoid. */
    void setButtonTargetId(const QString &plasmoidId);

    /** Enable/disable the search-time frecency bias (opt-in via ConfigSearch). */
    Q_INVOKABLE void setSearchUsesFrecency(bool enabled);

    /** Surface hidden apps in search results when @p enabled is true. */
    Q_INVOKABLE void setSearchShowsHidden(bool enabled);

    /** Opt-in per-activity scoping (favorites menus + folders). Off (default)
     *  feeds the store an empty activity so folders stay global. */
    Q_INVOKABLE void setActivityScopingEnabled(bool enabled);

    // --- Prefix mode commands ---

    /** Run @p command in the user's preferred terminal emulator using @p shell. */
    Q_INVOKABLE void runInTerminal(const QString &command, const QString &shell = QString());

    /** Run @p command via the configured shell without a terminal. */
    Q_INVOKABLE void runCommand(const QString &command, const QString &shell = QString());

    /** Returns list of installed shells from /etc/shells. */
    Q_INVOKABLE QStringList availableShells();

    /** Run a KRunner result by model index. Returns true if the UI should close. */
    Q_INVOKABLE bool runRunnerResult(int index);

    /** Run secondary action @p actionIndex on the KRunner result at @p index. */
    Q_INVOKABLE bool runRunnerAction(int index, int actionIndex);

    /** Substitution text for in-place runner results (calculator), else empty. */
    Q_INVOKABLE QString runnerSubstitutionText(int index);

    /** The KAStats favorite id for a KRunner result that maps to an application
     *  (its "applications:<storageId>" URL — apps and System Settings modules
     *  that ship a .desktop), so app-backed search results can be favorited like
     *  grid apps (#64). Empty when the result has no such URL (a calculator
     *  answer) or only a jump-list-action URL, which KAStats normalizes down to
     *  the bare storageId and so can't store distinctly. */
    [[nodiscard]] Q_INVOKABLE QString runnerResultFavoriteId(int index) const;

    /** Returns application-defined actions (jumplist) for the given storageId. */
    Q_INVOKABLE QVariantList appActions(const QString &storageId);

    /** Launch a specific app action by storageId and action index. */
    Q_INVOKABLE void launchAppAction(const QString &storageId, int actionIndex);

    /** True if KDE Discover is installed. */
    [[nodiscard]] Q_INVOKABLE bool isDiscoverAvailable() const;

    /** True if Discover has a backend that can manage the specified app. */
    [[nodiscard]] Q_INVOKABLE bool canManageInDiscover(const QString &storageId) const;

    /** Open KDE Discover focused on the application identified by @p storageId. */
    Q_INVOKABLE void openInDiscover(const QString &storageId);

    /** List directory contents at @p path. Returns {name, path, isDir, icon}. */
    Q_INVOKABLE QVariantList listDirectory(const QString &path);

    // --- System info ---

    /** Returns system/environment info for issue reporting. @p variant labels
     *  the running form factor (Center/Panel/Standalone). */
    Q_INVOKABLE QVariantMap systemInfo(const QString &variant = QStringLiteral("Center"));

Q_SIGNALS:
    /** Pin @p desktopFile to the Task Manager in-process. Emitted only when an
     *  applet hosts us (setInProcessTaskManagerPin); the applet's QML runs the
     *  real Kicker ContainmentInterface pin, which needs a live corona. */
    void addToTaskManagerRequested(const QString &desktopFile);
    /** The button-edit target changed (settings opened from a different center
     *  plasmoid while open); the settings window re-reads that instance's button. */
    void buttonTargetChanged();
    /** An async requestPlasmoidButtonAppearance() reply arrived. */
    void plasmoidButtonAppearanceChanged();

private:
    void applyRunnerFavorites();
    [[nodiscard]] QModelIndex runnerSourceIndex(int proxyIndex) const;
    /** Whether the center plasmoid's D-Bus helper is on the bus (gates the
     *  pin-to-taskmanager and button-edit features). */
    [[nodiscard]] bool plasmoidServicePresent() const;

    // Push the store's lists into the model on load + external change, and the
    // model's own mutations (hide, launch, recents) back into the store. The
    // equality guards on both sides stop the round-trip from looping.
    void wireLaunchState();

    AppModel m_appModel;
    AppFilterModel m_filterModel;
    LaunchStateStore m_launchState;
    FavoritesGroupedModel m_favoritesGrouped;
    MenuTreeModel m_menuTreeModel;
    // Built on first menuTreeModel() read (folders feature in use), not at startup.
    mutable bool m_menuTreeBuilt = false;
    // Feeds the current activity to m_launchState so folders are per-activity;
    // the store itself stays KConfig-only. Gated by m_activityScoping (opt-in):
    // off feeds an empty activity, keeping folders global.
    KActivities::Consumer *m_activities = nullptr;
    bool m_activityScoping = false;
    KRunner::ResultsModel *m_runnerModel = nullptr;
    RunnerFilterModel m_runnerFilterModel;
    UnifiedSearchModel m_searchModel;
    FrecencyProvider m_frecencyProvider;
    UsedAppsProvider m_usedApps;
    // Declared after m_usedApps: the tracker subscribes to it on construction.
    NewAppsTracker m_newAppsTracker;
    KSharedConfig::Ptr m_krunnerConfig;
    KConfigWatcher::Ptr m_krunnerWatcher;
    // Owns the standalone launcher window's layer-shell setup + positioning; the
    // Q_INVOKABLE configure/position methods forward here.
    WindowConfigurator m_window;
    // D-Bus object path of the plasmoid whose panel button the settings window
    // edits; set in the constructor to the shared path, retargeted per instance
    // by setButtonTargetId().
    QString m_buttonTargetPath;
    QVariantMap m_lastButtonAppearance;
    // Set by the hosting applet: pin in-process (emit) instead of over D-Bus.
    bool m_inProcessTaskManagerPin = false;
#ifdef APPGRID_UNIVERSAL_BUILD
    mutable UpdateChecker *m_updateChecker = nullptr;
#endif
};
