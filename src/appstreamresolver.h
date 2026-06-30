/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/**
 * Resolves a .desktop id to its canonical AppStream component id via the
 * AppStream::Pool that Kicker and Discover also use — it indexes metainfo from
 * every backend (distro/PackageKit, Flatpak, Snap), so one lookup works
 * regardless of where the app came from.
 *
 * The pool is built per-call and freed on return, so it never sits resident: a
 * session that never opens "Manage in Discover" maps nothing, and one that does
 * holds the ~30 MB catalogs only for the duration of the lookup. Unlike Kicker,
 * which keeps a process-global pool alive for the whole session — fine inside
 * plasmashell, wasteful for AppGrid's long-lived daemon and a rare action.
 */
namespace AppStreamResolver
{
/** Canonical AppStream component id for @p desktopId (e.g.
 *  "org.kde.kate.desktop"), or empty when no component matches. Loads the pool
 *  synchronously (~100 ms, hidden behind Discover's launch) and frees it on
 *  return, so the click resolves the exact component with no race. */
[[nodiscard]] QString resolve(const QString &desktopId);
}
