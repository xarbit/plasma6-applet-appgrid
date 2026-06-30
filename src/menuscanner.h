/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appmodel.h" // AppEntry
#include "menutree.h" // MenuTree::RawFolder

#include <QList>
#include <QVector>

/**
 * The single KServiceGroup walk feeding both AppGrid views (the flat app list
 * and the kmenuedit folder tree, #201). Both used to walk the XDG menu
 * independently with copy-pasted filter rules; this is the one place the menu
 * is read, so the no-display / non-application filtering lives once.
 *
 * One pass emits:
 *   - one AppEntry per service *occurrence* (an app reachable from several menu
 *     groups yields several), with its categories resolved for the active mode
 *     and the @c folderRelPath of the group it was reached through; and
 *   - one RawFolder per menu subgroup (every level), for the folder tree.
 *
 * AppModelAssembly::assemble() dedups the occurrences into the flat list;
 * MenuTree::build() nests folders + occurrences into the navigable tree. Both
 * are pure and unit-tested; the scan is the only KSycoca-touching part.
 */
namespace MenuScanner
{
struct RawScan {
    QList<MenuTree::RawFolder> folders; ///< every subgroup, all depths
    QVector<AppEntry> occurrences; ///< one per app placement, pre-dedup
};

/**
 * Walk the menu once. @p systemMode picks the category source per occurrence:
 * the top-level group caption (kmenuedit structure) vs. the desktop @c Categories
 * field mapped to clean buckets — matching AppModel's two modes exactly.
 */
[[nodiscard]] RawScan scan(bool systemMode);
}
