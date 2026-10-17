/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appstreamresolver.h"

#include "appgrid_debug.h"

#include <AppStreamQt/component-box.h>
#include <AppStreamQt/component.h>
#include <AppStreamQt/launchable.h>
#include <AppStreamQt/pool.h>

#include <QDebug>

#ifdef __GLIBC__
#include <malloc.h>
#endif

namespace AppStreamResolver
{
namespace
{
QString lookUp(const QString &desktopId)
{
    // A pool local to this lookup: Kicker keeps a process-global pool resident for
    // the whole session, but AppGrid is a long-lived daemon and this action is
    // rare, so the catalogs (~30 MB, mostly mmap of the shared .xb cache, and
    // growing with the system's Flatpak remotes) would sit in our footprint for an
    // app the user resolves maybe once. The pool destructs on return, dropping our
    // mapping; the ~100 ms synchronous load runs only on the click itself and is
    // hidden behind Discover's own launch.
    AppStream::Pool pool;
    if (!pool.load()) {
        qCWarning(APPGRID) << "AppStream pool load failed:" << pool.lastError();
        return {};
    }
    const auto components = pool.componentsByLaunchable(AppStream::Launchable::KindDesktopId, desktopId);
    for (const AppStream::Component &component : components) {
        if (!component.id().isEmpty()) {
            return component.id();
        }
    }
    return {};
}
}

QString resolve(const QString &desktopId)
{
    const QString id = lookUp(desktopId);
    // When the catalogs changed since the user's AppStream cache was written
    // (a Flatpak remote refreshed, an app installed), load() recompiles that
    // cache in our process: a few hundred MB of heap that the pool frees on
    // return, but that glibc keeps in the daemon's footprint until trimmed.
    // With a current cache there is little to give back.
#ifdef __GLIBC__
    malloc_trim(0);
#endif
    return id;
}
}
