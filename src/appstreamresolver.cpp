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
#include <QObject>

namespace AppStreamResolver
{
namespace
{
// Shared AppStream metadata pool plus its load state, as one unit so the two
// plasmoid variants in one plasmashell share a single warmed pool. Warmed
// asynchronously so the UI thread never blocks parsing metadata; queries gate
// on `ready` so we never read the pool mid-load.
struct SharedPool {
    AppStream::Pool pool;
    bool ready = false;
};

SharedPool &shared()
{
    static SharedPool instance;
    return instance;
}
}

void prefetch()
{
    static bool started = false;
    if (started) {
        return;
    }
    started = true;
    SharedPool &s = shared();
    QObject::connect(&s.pool, &AppStream::Pool::loadFinished, &s.pool, [](bool success) {
        shared().ready = success;
        if (!success) {
            qWarning() << "AppGrid: AppStream pool load failed:" << shared().pool.lastError();
        }
    });
    // Asynchronous so opening the menu never blocks on parsing metadata.
    s.pool.loadAsync();
}

QString resolve(const QString &desktopId)
{
    SharedPool &s = shared();
    if (!s.ready) {
        prefetch();
        return {};
    }
    const auto components = s.pool.componentsByLaunchable(AppStream::Launchable::KindDesktopId, desktopId);
    for (const AppStream::Component &component : components) {
        if (!component.id().isEmpty()) {
            return component.id();
        }
    }
    return {};
}
}
