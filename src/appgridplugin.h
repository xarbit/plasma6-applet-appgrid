/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <QRect>
#include <QVariantMap>

#include "appgridcontroller.h"

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

class QScreen;
class QWindow;
class AppGridPlugin;

/**
 * Minimal session-bus surface the center plasmoid exports so the standalone
 * daemon (which has no live applet/corona) can ask it to do things that need
 * one: pin to the Task Manager (Kicker, in-process) and report which screen the
 * panel icon is on (the "open on the panel's screen" option). Separate from
 * AppGridPlugin so only these reach the bus — not the applet's whole surface.
 */
class AppGridPlasmoidService : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", APPGRID_APP_ID ".Plasmoid")

public:
    explicit AppGridPlasmoidService(AppGridPlugin *plugin, QObject *parent = nullptr);

public Q_SLOTS:
    Q_SCRIPTABLE void requestAddToTaskManager(const QString &desktopFile);
    /** Name of the screen the panel icon sits on (empty if unknown). */
    Q_SCRIPTABLE QString panelScreenName() const;
    /** The panel button's appearance (read live from the plugin), for the daemon
     *  settings window to show. */
    Q_SCRIPTABLE QVariantMap buttonAppearance() const;
    /** Apply a new button appearance — forwarded to QML which writes the config. */
    Q_SCRIPTABLE void setButtonAppearance(const QVariantMap &values);

Q_SIGNALS:
    void addToTaskManagerRequested(const QString &desktopFile);
    void setButtonAppearanceRequested(const QVariantMap &values);

private:
    AppGridPlugin *const m_plugin;
};

/**
 * @brief Main Plasma applet plugin for the AppGrid application launcher.
 *
 * Thin Plasma::Applet wrapper around an AppGridController, which owns the
 * models and all of the applet-independent launcher logic. The applet keeps
 * the same Q_PROPERTY / Q_INVOKABLE surface QML already binds to and forwards
 * each call to the controller, so the two plasmoid variants need no QML change.
 * The pieces that genuinely need the applet stay here: the "Open in Compact
 * Mode" global shortcut, the activation-inversion that suppresses the native
 * popup in custom-window mode, and feeding the controller the containment's
 * screen for the "open on the panel's screen" path.
 *
 * The same controller backs the standalone `appgrid` executable (a separate
 * process whose window KWin can animate with any open/close effect); see
 * src/standalone.
 */
class AppGridPlugin : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(AppFilterModel *appsModel READ appsModel CONSTANT)
    Q_PROPERTY(FavoritesGroupedModel *favoritesGroupedModel READ favoritesGroupedModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *runnerModel READ runnerModel CONSTANT)
    Q_PROPERTY(QObject *runnerSourceModel READ runnerSourceModel CONSTANT)
    Q_PROPERTY(UnifiedSearchModel *searchModel READ searchModel CONSTANT)
    Q_PROPERTY(bool isWayland READ isWayland CONSTANT)
    Q_PROPERTY(bool isUniversalBuild READ isUniversalBuild CONSTANT)
#ifdef APPGRID_UNIVERSAL_BUILD
    Q_PROPERTY(UpdateChecker *updateChecker READ updateChecker CONSTANT)
#endif

public:
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    ~AppGridPlugin() override;

    [[nodiscard]] AppFilterModel *appsModel() const;
    [[nodiscard]] FavoritesGroupedModel *favoritesGroupedModel() const;
    [[nodiscard]] QAbstractItemModel *runnerModel() const;
    [[nodiscard]] QObject *runnerSourceModel() const;
    [[nodiscard]] UnifiedSearchModel *searchModel() const;
    [[nodiscard]] bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    [[nodiscard]] UpdateChecker *updateChecker() const;
#endif
    [[nodiscard]] bool isWayland() const;

    Q_INVOKABLE void notifyAppLaunched(const QString &storageId);
    // Pin to Task Manager runs in-process (Kicker's ContainmentInterface needs a
    // live applet): emit addToTaskManagerRequested so the variant's QML does it.
    // QML calls this for an in-process menu; the daemon reaches it over D-Bus via
    // requestAddToTaskManager (center variant only — see registerPlasmoidService).
    Q_INVOKABLE void addToTaskManager(const QString &desktopFile);
    Q_INVOKABLE void addToDesktop(const QString &desktopFile);
    // Always true for the plasmoid (it pins in-process); the daemon's controller
    // gates on its D-Bus helper instead.
    [[nodiscard]] Q_INVOKABLE bool canPinToTaskManager() const;
    [[nodiscard]] Q_INVOKABLE bool canAddToDesktop() const;

    /** Name of the screen this applet's containment (the panel) is on — the
     *  daemon's "open on the panel's screen" target. Empty if unknown. */
    [[nodiscard]] QString panelScreenName() const;
    Q_INVOKABLE void setSearchUsesFrecency(bool enabled);
    Q_INVOKABLE void setSearchShowsHidden(bool enabled);

    // --- Prefix mode commands ---

    Q_INVOKABLE void runInTerminal(const QString &command, const QString &shell = QString());
    Q_INVOKABLE void runCommand(const QString &command, const QString &shell = QString());
    Q_INVOKABLE QStringList availableShells();
    Q_INVOKABLE bool runRunnerResult(int index);
    Q_INVOKABLE bool runRunnerAction(int index, int actionIndex);
    Q_INVOKABLE QString runnerSubstitutionText(int index);
    [[nodiscard]] Q_INVOKABLE QString runnerResultFavoriteId(int index) const;
    Q_INVOKABLE QVariantList appActions(const QString &storageId);
    Q_INVOKABLE void launchAppAction(const QString &storageId, int actionIndex);
    [[nodiscard]] Q_INVOKABLE bool isDiscoverAvailable() const;
    [[nodiscard]] Q_INVOKABLE bool canManageInDiscover(const QString &storageId) const;
    Q_INVOKABLE void openInDiscover(const QString &storageId);
    Q_INVOKABLE QVariantList listDirectory(const QString &path);

    // --- System info ---

    Q_INVOKABLE QVariantMap systemInfo();

    /** Toggle the standalone `appgrid` daemon's window, launching the daemon if
     *  it is not yet running. The center variant routes its activation here so
     *  the launcher window is the separate-process one KWin can animate with any
     *  window open/close effect, like KRunner. */
    Q_INVOKABLE void toggleStandaloneWindow();

    /** Open the standalone daemon's settings window (launching the daemon first
     *  if it is not running). Wired to the panel icon's "Configure AppGrid…". */
    Q_INVOKABLE void configureStandaloneWindow();

    /** One-shot: copy this applet's settings into the standalone daemon's own
     *  config (appgridrc) the first time only, so a user upgrading from the
     *  in-process center variant keeps their settings. After this the daemon owns
     *  appgridrc; the applet config is no longer read. Idempotent (flagged). */
    Q_INVOKABLE void migrateConfigToStandalone();

    /** One-shot: seed the shared launch-state store (appgridrc) from this applet's
     *  old per-applet hidden/recent/known/launch-count lists, so a panel applet
     *  upgrading to the shared store keeps them. Only fills lists the store does
     *  not already have, so it never clobbers the daemon's or another applet's.
     *  Idempotent. */
    Q_INVOKABLE void migrateLaunchState();

    /** Push the current panel-button appearance (icon/customButtonImage/
     *  useCustomButtonImage/menuLabel) into the D-Bus helper so the daemon's
     *  settings window reads live values. Called by the center variant QML on
     *  config change. No-op without the helper (panel variant). */
    Q_INVOKABLE void updateButtonAppearanceCache(const QVariantMap &values);
    /** The cached panel-button appearance, read by the D-Bus helper. Held here
     *  (not the helper) so the QML push lands even before the helper exists. */
    [[nodiscard]] QVariantMap buttonAppearance() const;

Q_SIGNALS:
    /** Pin @p desktopFile to the Task Manager. Handled by the variant's QML
     *  (Kicker ContainmentInterface, which needs this applet). */
    void addToTaskManagerRequested(const QString &desktopFile);

    /** The daemon's settings window asked to change the panel button's
     *  appearance; the center variant QML writes it into Plasmoid.configuration. */
    void setButtonAppearanceRequested(const QVariantMap &values);

protected:
    bool m_useNativeActivation = false;

private:
    // Export this applet on the session bus (center variant) so the standalone
    // daemon can delegate the in-process Task Manager pin to it.
    void registerPlasmoidService();

    // Shared trigger for the standalone daemon: call @p dbusMethod on the running
    // instance, or launch the executable with @p launchArgs if it is not running.
    void triggerStandalone(const QString &dbusMethod, const QStringList &launchArgs, const QVariantList &dbusArgs = {});
    /** triggerStandalone() tagged with this applet's id, so the daemon knows which
     *  center plasmoid owns the launcher session / settings it opens (#191). */
    void triggerStandaloneAsOwner(const QString &dbusMethod, const QStringList &extraFlags = {});

    AppGridController m_controller;
    AppGridPlasmoidService *m_plasmoidService = nullptr;
    QVariantMap m_buttonAppearance;
    // Cached result of the running daemon's version probe (see triggerStandalone).
    bool m_daemonVersionChecked = false;
    bool m_daemonStale = false;
};
