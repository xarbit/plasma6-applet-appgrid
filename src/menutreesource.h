/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appmodel.h" // AppEntry
#include "menutree.h"

#include <QList>
#include <QVector>

/**
 * @brief Builds a MenuTree from an already-walked menu scan (issue #201).
 *
 * Pure adapter between the shared MenuScanner output and the tree assembler: it
 * maps app occurrences to RawApp and hands them, with the scanned folders, to
 * MenuTree::build. The menu itself is walked once in MenuScanner — this no
 * longer touches KSycoca.
 */
namespace MenuTreeSource
{

/** Assemble the navigable tree from the scanned @p folders and app
 *  @p occurrences (each carrying its folderRelPath). */
[[nodiscard]] MenuTree::Node fromScan(const QList<MenuTree::RawFolder> &folders, const QVector<AppEntry> &occurrences);

} // namespace MenuTreeSource
