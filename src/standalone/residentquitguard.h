/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QEvent>
#include <QObject>

/**
 * Keeps the daemon resident like KRunner. When the launcher's layer-shell window
 * hides as the last window, the Wayland platform posts a QEvent::Quit to
 * terminate the app — a path setQuitOnLastWindowClosed(false) does not cover, so
 * the daemon would die and the next launch would cold-start. This filter
 * swallows that stray Quit; only the explicit D-Bus Quit (an upgrade asking us
 * to step aside) sets @c allowQuit and lets the process exit.
 */
class ResidentQuitGuard : public QObject
{
public:
    bool allowQuit = false;

    // QObject::eventFilter is public; keep the same visibility so the override
    // doesn't narrow it (clang-tidy misc-override-with-different-visibility).
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Quit && !allowQuit) {
            return true;
        }
        return QObject::eventFilter(watched, event);
    }
};
