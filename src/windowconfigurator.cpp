/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "windowconfigurator.h"

#include "appgridconstants.h"
#include "plasmoidinterface.h"

#include <KWindowSystem>
#include <LayerShellQt/window.h>
#include <QCursor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QGuiApplication>
#include <QMargins>
#include <QScreen>
#include <QWindow>

namespace
{
// The translucent overlay and the theme background need an alpha channel.
constexpr int kAlphaBufferBits = 8;
// verticalOffsetPercent is a 0..100 percentage of the centering slack.
constexpr double kPercentScale = 100.0;

void enableAlphaChannel(QWindow *window)
{
    auto fmt = window->format();
    fmt.setAlphaBufferSize(kAlphaBufferBits);
    window->setFormat(fmt);
}

QScreen *screenForCursor()
{
    const QPoint pos = QCursor::pos();
    for (auto *screen : QGuiApplication::screens()) {
        if (screen->geometry().contains(pos)) {
            return screen;
        }
    }
    return nullptr;
}

QScreen *screenByName(const QString &name)
{
    if (name.isEmpty()) {
        return nullptr;
    }
    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (screen->name() == name) {
            return screen;
        }
    }
    return nullptr;
}

QScreen *activeScreen()
{
    // KWin is authoritative for the active output. QCursor::pos() is unreliable
    // on Wayland (no global pointer for a non-grabbing client), so match the
    // QScreen by the name KWin reports — exactly how KRunner finds its screen.
    auto msg =
        QDBusMessage::createMethodCall(AppGrid::KWinDbus::Service, AppGrid::KWinDbus::Path, AppGrid::KWinDbus::Interface, AppGrid::KWinDbus::ActiveOutputName);
    // Short timeout on the launcher-open path; fall back to the cursor's screen.
    const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, AppGrid::Dbus::OpenPathTimeoutMs);
    QScreen *screen = reply.isValid() ? screenByName(reply.value()) : nullptr;
    return screen ? screen : screenForCursor();
}

QScreen *panelScreen()
{
    // The daemon has no containment, so ask the plasmoid's helper which screen
    // the panel icon is on (the "open on the panel's screen" option).
    PlasmoidInterface plasmoid(AppGrid::PlasmoidDbus::Service, AppGrid::PlasmoidDbus::Path, QDBusConnection::sessionBus());
    plasmoid.setTimeout(AppGrid::Dbus::OpenPathTimeoutMs);
    QDBusPendingReply<QString> reply = plasmoid.panelScreenName();
    reply.waitForFinished();
    return reply.isValid() ? screenByName(reply.value()) : nullptr;
}
}

void WindowConfigurator::setLayerScope(const QString &scope)
{
    m_layerScope = scope;
}

void WindowConfigurator::configurePanelWayland(QWindow *window)
{
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    // m_layerScope decides KWin's WindowType: the standalone sets it
    // (setLayerScope) to a scope KWin maps to WindowType::Normal so every window
    // open/close effect animates it, like KRunner.
    layer->setScope(m_layerScope);
    layer->setExclusiveZone(0);
    // Anchor the top edge only: horizontally the surface stays centered (no
    // left/right anchor), vertically it sits at the top margin set by
    // positionPanelWindow() — that's how the user vertical offset applies to a
    // compositor-placed surface (like KRunner).
    layer->setAnchors(LayerShellQt::Window::AnchorTop);
}

void WindowConfigurator::configurePanelWindow(QWindow *window)
{
    if (!window) {
        return;
    }
    enableAlphaChannel(window);
    if (KWindowSystem::isPlatformWayland()) {
        configurePanelWayland(window);
    }
}

void WindowConfigurator::positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen)
{
    if (!window || !KWindowSystem::isPlatformWayland()) {
        return;
    }

    // useActiveScreen: the output under attention (KWin's active output). Else
    // the panel icon's screen (from the plasmoid helper); primary if no plasmoid.
    QScreen *target = useActiveScreen ? activeScreen() : panelScreen();
    if (!target) {
        target = QGuiApplication::primaryScreen();
    }
    if (!target) {
        return;
    }

    // Set the surface's screen EXPLICITLY (not wantsToBeOnActiveScreen): the
    // margin below is computed from this screen's height, so screen + margin must
    // agree. Letting the compositor pick the screen while QML computed the margin
    // off a lagging QScreen is what made the panel jump on a monitor switch.
    window->setScreen(target);
    auto *layer = LayerShellQt::Window::get(window);
    layer->setAnchors(LayerShellQt::Window::AnchorTop);
    // Pin the surface to the chosen output explicitly.
    layer->setScreen(target);

    // Center the full panel; the user vertical offset is a fraction of the slack
    // between the full panel and the screen edge. A compact panel uses the full
    // height too, so it hangs from the full panel's top.
    const int screenHeight = target->geometry().height();
    const int centered = (screenHeight - panelFullHeight) / 2;
    const int slack = qMax(0, centered);
    const int offset = qRound(verticalOffsetPercent / kPercentScale * slack);
    layer->setMargins(QMargins(0, qMax(0, centered + offset), 0, 0));
}
