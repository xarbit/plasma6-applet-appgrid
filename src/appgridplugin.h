/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <QRect>

class QAction;

namespace KRunner
{
class ResultsModel;
}

#include "appfiltermodel.h"
#include "appmodel.h"
#include "frecencyprovider.h"
#include "runnerfiltermodel.h"
#include "unifiedsearchmodel.h"

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

class QScreen;
class QWindow;

/**
 * @brief Main Plasma applet plugin for the AppGrid application launcher.
 *
 * Provides a centered application grid overlay with category filtering,
 * search, blur effects, and session management actions. Exposes Q_INVOKABLE
 * methods for QML to configure the overlay window, manage blur, launch
 * session actions, and integrate with the desktop (task manager, desktop icons).
 */
class AppGridPlugin : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(AppFilterModel *appsModel READ appsModel CONSTANT)
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
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);

    [[nodiscard]] AppFilterModel *appsModel() const;
    [[nodiscard]] QAbstractItemModel *runnerModel() const;
    [[nodiscard]] QObject *runnerSourceModel() const;
    [[nodiscard]] UnifiedSearchModel *searchModel() const;
    [[nodiscard]] bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    [[nodiscard]] UpdateChecker *updateChecker() const;
#endif
    [[nodiscard]] bool isWayland() const;

    // --- Window management ---

    /** Configure @p window as an overlay (LayerShell on Wayland, flags on X11). */
    Q_INVOKABLE void configureWindow(QWindow *window);

    /** Update which screen the Wayland overlay appears on (no-op on X11). */
    Q_INVOKABLE void updateWindowScreen(QWindow *window, bool useActiveScreen);

    /** Returns the target screen geometry for the overlay (used by QML on X11). */
    Q_INVOKABLE QRect targetScreenGeometry(bool useActiveScreen);

    /** Set a rounded-rect blur region on @p window matching the panel geometry. */
    Q_INVOKABLE void setBlurBehind(QWindow *window, bool enable, int x, int y, int w, int h, int radius);

    /**
     * Restrict pointer input on @p window to the rectangle (x,y,w,h). The
     * rest of the window becomes pass-through — events fall through to the
     * surface below (e.g. the panel/taskbar/desktop under our full-screen
     * layer overlay). If @p w or @p h is zero, the mask is cleared and the
     * entire window receives input again.
     *
     * Used while a drag-out is in flight: the centred grid panel keeps full
     * input (so internal favorites reorder still works) while the surrounding
     * dim overlay becomes pass-through so the user can drop on external
     * targets that are otherwise covered by AppGrid.
     */
    Q_INVOKABLE void setInputRect(QWindow *window, int x, int y, int w, int h);

    /**
     * Broadcast an app launch to the system-wide KActivities database so
     * other Plasma launchers (Kickoff, KRunner, etc.) count AppGrid as a
     * contributing launcher. AppGrid does NOT read this data back; it's a
     * one-way courtesy notification. See #95 for the rationale.
     */
    Q_INVOKABLE void notifyAppLaunched(const QString &storageId);

    /**
     * Enable/disable the search-time frecency bias (opt-in via ConfigSearch).
     * Routes to FrecencyProvider (start/stop the KAStats query) and to the
     * filter model's tiebreak switch. Idempotent; safe to call on every
     * config change.
     */
    Q_INVOKABLE void setSearchUsesFrecency(bool enabled);

    /** Surface hidden apps in search results when @p enabled is true
     *  (the default). False filters them out of both AppFilterModel
     *  and RunnerFilterModel — matching the grid hide. */
    Q_INVOKABLE void setSearchShowsHidden(bool enabled);

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

    /**
     * For runner results where the user typically wants to keep iterating
     * on the search bar (calculator: paste the result and keep typing),
     * returns the text to substitute into the query. Empty for runner
     * rows whose normal action is "run" (file open, web shortcut, …).
     */
    Q_INVOKABLE QString runnerSubstitutionText(int index);

    /** Returns application-defined actions (jumplist) for the given storageId. */
    Q_INVOKABLE QVariantList appActions(const QString &storageId);

    /** Launch a specific app action by storageId and action index. */
    Q_INVOKABLE void launchAppAction(const QString &storageId, int actionIndex);

    /** True if KDE Discover is installed. Standalone check; per-app
     *  manageability is queried separately via canManageInDiscover. */
    [[nodiscard]] Q_INVOKABLE bool isDiscoverAvailable() const;

    /** True if Discover has a backend that can manage the specified
     *  app (currently PackageKit for native packages, Flatpak for
     *  Flatpak apps). Used to gate the "Manage in Discover" menu item
     *  so it only appears for apps Discover will actually open. */
    [[nodiscard]] Q_INVOKABLE bool canManageInDiscover(const QString &storageId) const;

    /** Open KDE Discover focused on the application identified by
     *  @p storageId via the appstream:// URL scheme. */
    Q_INVOKABLE void openInDiscover(const QString &storageId);

    /** List directory contents at @p path. Returns a list of {name, path, isDir, icon}. */
    Q_INVOKABLE QVariantList listDirectory(const QString &path);

    // --- System info ---

    /** Returns system/environment info for issue reporting. */
    Q_INVOKABLE QVariantMap systemInfo();

Q_SIGNALS:
    /**
     * Emitted when the user triggers the secondary "Open in Compact Mode"
     * global shortcut. Ships unbound; user assigns the key in System
     * Settings → Keyboard → Shortcuts → AppGrid. QML reacts by opening
     * the launcher with the compact-mode override active for that
     * session, regardless of the persisted `hideGridWhenEmpty` config.
     */
    void compactActivated();

protected:
    bool m_useNativeActivation = false;

private:
    /**
     * Register the secondary "Open in Compact Mode" global shortcut on
     * this applet. Deferred from the constructor so the applet's plugin
     * metadata (used as the KGlobalAccel component identity) is fully
     * resolved by the time we register. Called only by the center variant;
     * the popup variant skips it via the m_useNativeActivation gate.
     */
    void registerCompactShortcut();

    // --- Platform-specific window helpers ---

    [[nodiscard]] QScreen *screenForCursor() const;
    [[nodiscard]] QScreen *screenForPanel() const;

    void configureWayland(QWindow *window);
#ifdef APPGRID_X11_SUPPORT
    void configureX11(QWindow *window);
#endif
    void updateScreenWayland(QWindow *window, QScreen *target, bool useActiveScreen);

    // Maps a UnifiedSearchModel runner-row index (proxy) to a ResultsModel
    // source QModelIndex. Returns an invalid QModelIndex on out-of-range so
    // callers can early-out without repeating the bounds check.
    [[nodiscard]] QModelIndex runnerSourceIndex(int proxyIndex) const;

    AppModel m_appModel;
    AppFilterModel m_filterModel;
    KRunner::ResultsModel *m_runnerModel = nullptr;
    RunnerFilterModel m_runnerFilterModel;
    UnifiedSearchModel m_searchModel;
    FrecencyProvider m_frecencyProvider;
    QAction *m_compactAction = nullptr;
#ifdef APPGRID_UNIVERSAL_BUILD
    mutable UpdateChecker *m_updateChecker = nullptr;
#endif
};
