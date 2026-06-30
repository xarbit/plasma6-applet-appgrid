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
 * variants running in one plasmashell share one pool. It loads synchronously on
 * the first resolve() and never before — exactly Kickoff/Kicker's pattern, where
 * the pool is built only when the user invokes "Manage in Discover". A session
 * that never opens that action never maps the ~25 MB metadata catalogs.
 */
namespace AppStreamResolver
{
/** Canonical AppStream component id for @p desktopId (e.g.
 *  "org.kde.kate.desktop"), or empty when the pool has no matching component.
 *  Loads the pool synchronously on the first call (one brief parse), so the very
 *  first "Manage in Discover" click resolves the exact component with no race. */
[[nodiscard]] QString resolve(const QString &desktopId);
}
