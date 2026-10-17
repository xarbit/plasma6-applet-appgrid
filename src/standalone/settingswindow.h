/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QStringList>

class AppGridConfig;
class AppGridController;
class QQmlApplicationEngine;
class QQuickWindow;

/**
 * The daemon's settings window. It runs in its OWN QQmlApplicationEngine using
 * the desktop colour platform (unlike the launcher's Plasma theme), created on
 * first show() and destroyed the moment it closes — never left hidden, because a
 * lingering qqc2-desktop-style window crashes when a later launcher hide
 * re-lays-out its stale style items. Recreated fresh on the next open
 * (ConfigWindow re-syncs from live on show), so nothing is lost.
 */
class SettingsWindow
{
public:
    SettingsWindow(AppGridConfig *config, AppGridConfig *buffer, AppGridController *controller);
    ~SettingsWindow();

    SettingsWindow(const SettingsWindow &) = delete;
    SettingsWindow &operator=(const SettingsWindow &) = delete;

    void show();

private:
    [[nodiscard]] QQuickWindow *window() const;
    // Every setting of the shared schema the window buffers for Apply/Cancel:
    // all of them but the panel button's appearance, which the plasmoid
    // owns (#191). Read from the generated config, so a new setting is
    // buffered without being listed anywhere.
    [[nodiscard]] QStringList editableKeys() const;
    void load();
    void destroy();

    AppGridConfig *const m_config;
    AppGridConfig *const m_buffer;
    AppGridController *const m_controller;
    QQmlApplicationEngine *m_engine = nullptr;
};
