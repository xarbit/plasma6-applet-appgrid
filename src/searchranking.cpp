/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "searchranking.h"

#include <cstdlib>

namespace SearchRanking
{
QString singularize(const QString &query)
{
    if (query.size() < 4 || !query.endsWith(QLatin1Char('s'), Qt::CaseInsensitive)) {
        return {};
    }
    return query.chopped(1);
}

bool containsAtWordBoundary(const QString &haystack, const QString &needle)
{
    if (needle.isEmpty()) {
        return false;
    }
    int from = 0;
    while (true) {
        const int idx = haystack.indexOf(needle, from, Qt::CaseInsensitive);
        if (idx < 0) {
            return false;
        }
        if (idx == 0 || !haystack.at(idx - 1).isLetterOrNumber()) {
            return true;
        }
        from = idx + 1;
    }
}

int relevance(const QString &name,
              const QString &genericName,
              const QString &comment,
              const QStringList &keywords,
              const QStringList &categories,
              const QString &query)
{
    if (query.isEmpty()) {
        return TierNoMatch;
    }

    if (name.startsWith(query, Qt::CaseInsensitive)) {
        return TierNamePrefix;
    }
    if (containsAtWordBoundary(name, query)) {
        return TierNameWordBoundary;
    }

    if (containsAtWordBoundary(genericName, query)) {
        return TierGeneric;
    }
    // Fallback: many .desktop files omit GenericName entirely (third-party
    // apps especially), leaving Comment as the only descriptive field. Treat
    // it as tier 2 only when GenericName is missing so apps that properly fill
    // both don't get double-counted.
    if (genericName.isEmpty() && containsAtWordBoundary(comment, query)) {
        return TierGeneric;
    }

    for (const auto &kw : keywords) {
        if (kw.contains(query, Qt::CaseInsensitive)) {
            return TierKeyword;
        }
    }

    // Categories share tier 3: typing "game" or "office" should pull in the
    // matching freedesktop category siblings (Game, ArcadeGame, OfficeApp …).
    // Plural queries also test the singularized form so "games" matches
    // "Game" / "ArcadeGame" — see singularize().
    const QString singularQuery = singularize(query);
    for (const auto &cat : categories) {
        if (cat.contains(query, Qt::CaseInsensitive)) {
            return TierKeyword;
        }
        if (!singularQuery.isEmpty() && cat.contains(singularQuery, Qt::CaseInsensitive)) {
            return TierKeyword;
        }
    }

    if (name.contains(query, Qt::CaseInsensitive)) {
        return TierNameMidword;
    }

    return TierNoMatch;
}

QString completionWord(const QString &text, const QString &query)
{
    if (query.isEmpty() || text.isEmpty()) {
        return {};
    }
    const QString folded = query.toCaseFolded();
    const int n = text.size();
    int i = 0;
    while (i < n) {
        while (i < n && !text.at(i).isLetterOrNumber()) {
            ++i;
        }
        const int start = i;
        while (i < n && text.at(i).isLetterOrNumber()) {
            ++i;
        }
        if (i - start > query.size()) {
            const QString word = text.mid(start, i - start);
            if (word.toCaseFolded().startsWith(folded)) {
                return word;
            }
        }
    }
    return {};
}

namespace
{
// The in-tier order: starred favourite, role default, usage, mime default.
int compareInTier(const ResultRank &a, const ResultRank &b)
{
    if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
    }
    if (a.isPreferred != b.isPreferred) {
        return a.isPreferred ? -1 : 1;
    }
    if (a.usage != b.usage) {
        return a.usage > b.usage ? -1 : 1;
    }
    if (a.isDefault != b.isDefault) {
        return a.isDefault ? -1 : 1;
    }
    return 0;
}
}

int compare(const ResultRank &a, const ResultRank &b)
{
    if (a.relevance == b.relevance) {
        return compareInTier(a, b);
    }
    // Promotion: a result may climb exactly one tier when it beats the other
    // on the in-tier key (so a frequently used generic-name match outranks a
    // never-launched name match). Endpoint tiers are inviolate:
    //   TierNamePrefix — must always win
    //   TierNameMidword — must always lose
    // and the generic<->keyword boundary is never crossed: keywords are a
    // marketing tag bag, generic/Comment text is a semantic signal. That
    // leaves only the name word-boundary <-> generic-name pair.
    const bool endpointInvolved =
        a.relevance == TierNamePrefix || b.relevance == TierNamePrefix || a.relevance == TierNameMidword || b.relevance == TierNameMidword;
    const bool keywordVsGenericBoundary =
        (a.relevance == TierGeneric && b.relevance == TierKeyword) || (a.relevance == TierKeyword && b.relevance == TierGeneric);
    if (!endpointInvolved && !keywordVsGenericBoundary && std::abs(a.relevance - b.relevance) <= 1) {
        if (const int inTier = compareInTier(a, b); inTier != 0) {
            return inTier;
        }
    }
    return a.relevance < b.relevance ? -1 : 1;
}
}
