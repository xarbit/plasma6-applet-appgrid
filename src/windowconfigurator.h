/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

class QWindow;

/**
 * @brief Owns the standalone daemon's launcher-window surface configuration.
 *
 * Layer-shell setup (Wayland; Plasma 6.8 has no X11 session) and the atomic
 * screen-pick-plus-vertical-center positioning the panel needs on a
 * multi-monitor setup. Pure side effects on a QWindow + a little KWin/plasmoid
 * D-Bus to find the right output; no identity or signals, so a plain class, not
 * a QObject. AppGridController forwards its Q_INVOKABLEs here. The stateless
 * screen-picking helpers live as free functions in the .cpp.
 */
class WindowConfigurator
{
public:
    /** Layer-shell scope the next configurePanelWindow() applies. The standalone
     *  sets a scope KWin maps to WindowType::Normal so the window open/close
     *  effect animates it like KRunner. Must be set before configurePanelWindow(). */
    void setLayerScope(const QString &scope);

    /** Configure @p window as the centered, content-sized panel surface that
     *  carries the theme background and blur. */
    void configurePanelWindow(QWindow *window);

    /** Place the panel surface on the right screen and center it vertically in one
     *  atomic step (KRunner's model): pick the target screen — KWin's active
     *  output when @p useActiveScreen, else the panel icon's screen — set the layer
     *  surface to it explicitly, and set the top margin from THAT screen's height:
     *  (height - @p panelFullHeight)/2 plus @p verticalOffsetPercent of the slack.
     *  Wayland-only. */
    void positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen);

private:
    // The only stateful step: the layer scope decides KWin's WindowType.
    void configurePanelWayland(QWindow *window);

    // Always set by setLayerScope() before configurePanelWayland() reads it; the
    // standalone is the only caller and uses "appgrid-standalone".
    QString m_layerScope = QStringLiteral("appgrid-standalone");
};
