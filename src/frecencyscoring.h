/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QString>
#include <QStringList>

/**
 * Pure scoring for FrecencyProvider — kept free of KActivities so it can be
 * unit-tested without a live KAStats database. Turns the ordered (best-first)
 * list of KAStats resource URIs into a storageId → rank map.
 */
namespace FrecencyScoring
{
/**
 * Rank-score an ordered (best-first) list of "applications:<id>" resource URIs.
 * The top row scores `count`, the last scores 1 — stable ordering even as the
 * absolute KAStats scores drift. Each app is indexed under both its "org.kde."
 * and bare spelling (different launchers/eras store e.g. konsole either way),
 * and a higher score is never demoted when two resources normalise to the same
 * key. Resources without the applications: prefix are skipped.
 */
[[nodiscard]] QHash<QString, int> scoresFromResources(const QStringList &orderedResources);
}
