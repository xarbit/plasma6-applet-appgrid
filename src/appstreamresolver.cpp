/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appstreamresolver.h"

#include <AppStreamQt/component-box.h>
#include <AppStreamQt/component.h>
#include <AppStreamQt/launchable.h>
#include <AppStreamQt/pool.h>

#include <QDebug>

namespace AppStreamResolver
{
namespace
{
// The process-wide AppStream pool, loaded synchronously the first time it's
// asked for and never before — the way Kickoff/Kicker build theirs only when
// the user invokes "Manage in Discover". The load() blocks once while it parses
// the catalogs; the user has just clicked the action, so that's the right moment
// to pay it (and it resolves on the first try, with no async race).
AppStream::Pool &pool()
{
    static AppStream::Pool instance;
    [[maybe_unused]] static const bool loaded = [] {
        if (!instance.load()) {
            qWarning() << "AppGrid: AppStream pool load failed:" << instance.lastError();
        }
        return true;
    }();
    return instance;
}
}

QString resolve(const QString &desktopId)
{
    const auto components = pool().componentsByLaunchable(AppStream::Launchable::KindDesktopId, desktopId);
    for (const AppStream::Component &component : components) {
        if (!component.id().isEmpty()) {
            return component.id();
        }
    }
    return {};
}
}
