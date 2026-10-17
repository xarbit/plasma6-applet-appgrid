/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <QVariantMap>

#include "appgridcontroller.h"

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
 * Thin Plasma::Applet that owns an AppGridController and exposes it (the
 * `controller` property). Both plasmoid variants drive GridPanel through that
 * controller — the same object the standalone `appgrid` executable injects — so
 * there is one implementation of the launcher surface, no per-variant forwarding.
 *
 * The applet adds only the pieces that genuinely need a live applet + corona:
 * the "Open in Compact Mode" global shortcut, the activation-inversion that
 * suppresses the native popup in custom-window mode, the in-process Task Manager
 * pin (it marks the controller and runs the pin from QML), the containment's
 * screen for "open on the panel's screen", the panel-button appearance helper,
 * and the one-shot config / launch-state migrations.
 */
class AppGridPlugin : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(AppGridController *controller READ controller CONSTANT)

public:
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    ~AppGridPlugin() override;

    /** The launcher controller QML drives (models + every Q_INVOKABLE), created
     *  on first use. Only the panel variant hosts the launcher and so reads it;
     *  the center variant never does, which keeps the app scan, KRunner, KAStats
     *  and the launch-state store out of plasmashell for it. The applet pins the
     *  Task Manager in-process, so it marks the controller when creating it. */
    [[nodiscard]] AppGridController *controller();

    /** Name of the screen this applet's containment (the panel) is on — the
     *  daemon's "open on the panel's screen" target. Empty if unknown. */
    [[nodiscard]] QString panelScreenName() const;

    /** System info for the i: view, tagged with this variant (Panel/Center). */
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
     *  old per-applet hidden/recent/launch-count lists, so a panel applet
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
    /** The daemon's settings window asked to change the panel button's
     *  appearance; the center variant QML writes it into Plasmoid.configuration. */
    void setButtonAppearanceRequested(const QVariantMap &values);

    /** Pin @p desktopFile to the Task Manager, which needs this live applet's
     *  corona: requested by the daemon over D-Bus, or by the panel variant's own
     *  context menu (through the controller). TaskManagerPinner runs it. */
    void addToTaskManagerRequested(const QString &desktopFile);

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

    AppGridController *m_controller = nullptr; // see controller()
    AppGridPlasmoidService *m_plasmoidService = nullptr;
    QVariantMap m_buttonAppearance;
    // Cached result of the running daemon's version probe (see triggerStandalone).
    bool m_daemonVersionChecked = false;
    bool m_daemonStale = false;
};
