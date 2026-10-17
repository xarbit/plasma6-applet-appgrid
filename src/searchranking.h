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

/** First whitespace/punctuation-delimited word in @p text whose case-folded
 *  form starts with (case-folded) @p query and is strictly longer than it, in
 *  its original casing; empty if none. Drives the search field's inline
 *  completion ("te" against "Terminal emulator" → "Terminal"). */
[[nodiscard]] QString completionWord(const QString &text, const QString &query);

/** What orders two results of the same search, apart from their names. */
struct ResultRank {
    int relevance = TierNoMatch;
    // Launch count, or the frecency score when that ranking is enabled.
    int usage = 0;
    // Starred in AppGrid's favourites.
    bool isFavorite = false;
    // A role default (browser / mail / file manager / terminal).
    bool isPreferred = false;
    // A mimeapps.list default for some type.
    bool isDefault = false;
};

/** Order two results of the same search: <0 when @p a ranks first, >0 when
 *  @p b does, 0 when they tie (the caller then orders them by name).
 *
 *  Within a tier, a starred favourite wins, then a role default (the default
 *  terminal, browser, ...), then usage, then a mime default. Across tiers the
 *  better tier wins, except that between the name word-boundary and
 *  generic-name tiers the same comparison may lift a result exactly one tier
 *  — so typing "terminal" puts your favourite, else default, else most used
 *  terminal first. Promotion and the in-tier order use one key, which keeps this a
 *  strict weak ordering (a sort over it is well defined). */
[[nodiscard]] int compare(const ResultRank &a, const ResultRank &b);
}
