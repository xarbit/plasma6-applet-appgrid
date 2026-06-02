/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>

/**
 * Pure search-relevance scoring extracted from AppFilterModel so the tier
 * logic can be unit-tested with plain strings, independent of the proxy
 * model and its role data.
 */
namespace SearchRanking
{
// Relevance tiers (lower = better match). Shared by relevance() and the
// promotion guard in AppFilterModel::lessThan().
inline constexpr int TierNamePrefix = 0; // name starts with query
inline constexpr int TierNameWordBoundary = 1; // word-boundary substring in name
inline constexpr int TierGeneric = 2; // word-boundary in generic name / Comment fallback
inline constexpr int TierKeyword = 3; // keyword or category contains query
inline constexpr int TierNameMidword = 4; // mid-word substring fallback
inline constexpr int TierNoMatch = 5; // filtered out

/** Naive plural strip: "games" → "game", or empty when not applicable.
 *  Capped at queries of 4+ chars so short tokens like "es"/"is"/"os" don't
 *  lose their final letter. No real stemmer — covers the common English case. */
[[nodiscard]] QString singularize(const QString &query);

/** True when @p needle appears at a word boundary in @p haystack — at
 *  position 0 or just after a non-alphanumeric character. */
[[nodiscard]] bool containsAtWordBoundary(const QString &haystack, const QString &needle);

/** Relevance tier for an app's text fields against @p query. Lower is a
 *  better match; TierNoMatch means it should be filtered out. */
[[nodiscard]] int relevance(const QString &name,
                            const QString &genericName,
                            const QString &comment,
                            const QStringList &keywords,
                            const QStringList &categories,
                            const QString &query);
}
