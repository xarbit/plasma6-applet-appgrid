/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>

class QWindow;

/**
 * @brief Owns the standalone daemon's launcher-window surface configuration.
 *
 * Layer-shell setup (Wayland; Plasma 6.8 has no X11 session) and the atomic
 * screen-pick-plus-vertical-center positioning the panel needs on a
 * multi-monitor setup: side effects on a QWindow and a little KWin/plasmoid
 * D-Bus to find the right output. The daemon owns one and hands it to its QML;
 * the screen-picking helpers are free functions in the .cpp.
 */
class WindowConfigurator : public QObject
{
    Q_OBJECT

public:
    /** @p layerScope decides KWin's WindowType for the window: the daemon uses a
     *  scope KWin maps to WindowType::Normal, so every window open/close effect
     *  animates it like KRunner. */
    explicit WindowConfigurator(const QString &layerScope, QObject *parent = nullptr);

    /** Configure @p window as the centered, content-sized panel surface that
     *  carries the theme background and blur. */
    Q_INVOKABLE void configurePanelWindow(QWindow *window);

    /** Place the panel surface on the right screen and center it vertically in one
     *  atomic step (KRunner's model): pick the target screen — KWin's active
     *  output when @p useActiveScreen, else the panel icon's screen — set the layer
     *  surface to it explicitly, and set the top margin from THAT screen's height:
     *  (height - @p panelFullHeight)/2 plus @p verticalOffsetPercent of the slack.
     *  Wayland-only. */
    // A Q_INVOKABLE for QML: must stay a non-static member for moc.
    // cppcheck-suppress functionStatic
    Q_INVOKABLE void positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen);

private:
    // The only stateful step: the layer scope decides KWin's WindowType.
    void configurePanelWayland(QWindow *window);

    const QString m_layerScope;
};
