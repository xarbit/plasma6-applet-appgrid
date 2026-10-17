/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantMap>

class AppGridPlugin;

/**
 * Minimal session-bus surface the center plasmoid exports so the standalone
 * daemon (which has no live applet/corona) can ask it to do things that need
 * one: pin to the Task Manager (Kicker, in-process), report which screen the
 * panel icon is on (the "open on the panel's screen" option) and read or set
 * the panel button's appearance. Separate from AppGridPlugin so only these
 * reach the bus — not the applet's whole surface.
 */
class AppGridPlasmoidService : public QObject
{
    Q_OBJECT

public:
    explicit AppGridPlasmoidService(AppGridPlugin *plugin, QObject *parent = nullptr);

    // dev.xarbit.appgrid.Plasmoid (src/dbus), exported through PlasmoidAdaptor.
    void requestAddToTaskManager(const QString &desktopFile);
    /** Name of the screen the panel icon sits on (empty if unknown). */
    [[nodiscard]] QString panelScreenName() const;
    /** The panel button's appearance (read live from the plugin), for the daemon
     *  settings window to show. */
    [[nodiscard]] QVariantMap buttonAppearance() const;
    /** Apply a new button appearance — forwarded to QML which writes the config. */
    void setButtonAppearance(const QVariantMap &values);

Q_SIGNALS:
    void addToTaskManagerRequested(const QString &desktopFile);
    void setButtonAppearanceRequested(const QVariantMap &values);

private:
    AppGridPlugin *const m_plugin;
};
