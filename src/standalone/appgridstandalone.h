/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>

/**
 * @brief Single-instance D-Bus surface for the standalone `appgrid` executable.
 *
 * Registered on the session bus at service `dev.xarbit.appgrid`, object
 * `/Standalone`. A second invocation of the binary finds the service already
 * taken, calls Toggle() on the running instance and exits — so the daemon
 * behaves like KRunner (one process, toggled by a shortcut/launcher). The
 * Show/Hide/Toggle slots are exported as D-Bus methods and also emit the
 * matching Qt signals the QML entry connects to.
 */
class AppGridStandalone : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "dev.xarbit.appgrid.Standalone")

public:
    explicit AppGridStandalone(QObject *parent = nullptr);

    static QString serviceName();
    static QString objectPath();
    static QString interfaceName();

    /** True if registration succeeded (we are the primary instance). */
    bool registerService();

    /** Ask an already-running primary instance to toggle its window. @p plasmoidId
     *  is the center plasmoid that opened the launcher (empty for a terminal
     *  launch), which becomes the owner the settings button rows edit. */
    static bool callToggleOnRunningInstance(const QString &plasmoidId = QString());

    /** Ask an already-running primary instance to toggle in compact mode (the
     *  global "Open in Compact Mode" shortcut re-launching `appgrid --compact`). */
    static bool callToggleCompactOnRunningInstance(const QString &plasmoidId = QString());

    /** Ask an already-running primary instance to open its config window. */
    static bool callConfigureOnRunningInstance(const QString &plasmoidId = QString());

    /** Open the daemon's own settings window in-process (the launcher's Settings
     *  action), keeping the current owner plasmoid — not a D-Bus entry point. */
    Q_INVOKABLE void openSettings();

public Q_SLOTS:
    Q_SCRIPTABLE void Show();
    Q_SCRIPTABLE void Hide();
    /** @p plasmoidId — the center plasmoid that owns this launcher session
     *  (empty for a terminal launch), so the settings button rows edit it. */
    Q_SCRIPTABLE void Toggle(const QString &plasmoidId = QString());
    Q_SCRIPTABLE void ToggleCompact(const QString &plasmoidId = QString());
    /** Open the settings window from a specific center plasmoid's "Configure
     *  Launcher" (@p plasmoidId; empty clears the owner). */
    Q_SCRIPTABLE void Configure(const QString &plasmoidId = QString());
    /** Build version of this daemon — the plasmoid compares it against the
     *  installed build to detect a stale daemon left over from an upgrade. */
    Q_SCRIPTABLE QString Version() const;
    /** Quit the daemon (so a freshly-installed build can take its place). */
    Q_SCRIPTABLE void Quit();

Q_SIGNALS:
    void showRequested();
    void hideRequested();
    void toggleRequested(const QString &plasmoidId);
    void toggleCompactRequested(const QString &plasmoidId);
    void configureRequested(const QString &plasmoidId);
    /** The launcher's own Settings action — open the window, keep the owner. */
    void openSettingsRequested();
    void quitRequested();
};
