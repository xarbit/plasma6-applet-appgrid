/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/**
 * Resolves a .desktop id to its canonical AppStream component id via the
 * shared AppStream::Pool that Kicker and Discover also use — it indexes
 * metainfo from every backend (distro/PackageKit, Flatpak, Snap), so one
 * lookup works regardless of where the app came from.
 *
 * The pool is process-global (a function-local static) so the two plasmoid
 * variants running in one plasmashell share a single warmed pool. Extracted
 * from AppGridPlugin so that global state lives in one focused unit instead
 * of hidden behind file-static functions in the applet.
 */
namespace AppStreamResolver
{
/** Kick off the one-time async pool load (idempotent, cheap no-op afterwards).
 *  Call it the moment a Discover-manageable app's menu opens, so the imminent
 *  "Manage in Discover" click resolves the exact component instead of racing the
 *  load. NOT called at startup — a session that never opens such a menu never
 *  maps the ~25 MB metadata catalogs. */
void prefetch();

/** Canonical AppStream component id for @p desktopId (e.g.
 *  "org.kde.kate.desktop"), or empty when the pool has no matching component or
 *  is still loading. Triggers prefetch() itself if nothing did yet. */
[[nodiscard]] QString resolve(const QString &desktopId);
}
