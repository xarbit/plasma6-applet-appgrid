/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appmodel.h" // AppEntry

#include <QStringList>
#include <QVector>

/**
 * Pure post-processing for AppModel::loadApplications, free of KService so it
 * can be unit-tested without KSycoca. The KServiceGroup walk produces one
 * AppEntry per service *occurrence* (an app reachable from several menu groups
 * yields several occurrences); this assembles them into the final model state.
 */
namespace AppModelAssembly
{
struct Result {
    QVector<AppEntry> apps; ///< deduplicated, alphabetically sorted (case-insensitive)
    QStringList categories; ///< sorted, unique union of every kept app's categories
};

/**
 * Deduplicate occurrences by storageId and finalise ordering.
 *
 * First occurrence of a storageId wins its fields. In @p systemMode a repeat
 * occurrence merges its categories into the existing entry (an app in several
 * menu groups accumulates all of them); in simple mode the repeat is dropped
 * (the first occurrence already carries the app's full category set). Empty
 * storageIds are skipped; an empty *name* still claims the storageId (so a
 * later, named occurrence of the same id is suppressed — mirrors the original
 * walk). The result is sorted by name with a case-insensitive QCollator.
 */
[[nodiscard]] Result assemble(const QVector<AppEntry> &occurrences, bool systemMode);
}
