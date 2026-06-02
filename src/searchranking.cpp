/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "searchranking.h"

namespace SearchRanking
{
QString singularize(const QString &query)
{
    if (query.size() < 4 || !query.endsWith(QLatin1Char('s'), Qt::CaseInsensitive))
        return {};
    return query.chopped(1);
}

bool containsAtWordBoundary(const QString &haystack, const QString &needle)
{
    if (needle.isEmpty())
        return false;
    int from = 0;
    while (true) {
        const int idx = haystack.indexOf(needle, from, Qt::CaseInsensitive);
        if (idx < 0)
            return false;
        if (idx == 0 || !haystack.at(idx - 1).isLetterOrNumber())
            return true;
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
    if (query.isEmpty())
        return TierNoMatch;

    if (name.startsWith(query, Qt::CaseInsensitive))
        return TierNamePrefix;
    if (containsAtWordBoundary(name, query))
        return TierNameWordBoundary;

    if (containsAtWordBoundary(genericName, query))
        return TierGeneric;
    // Fallback: many .desktop files omit GenericName entirely (third-party
    // apps especially), leaving Comment as the only descriptive field. Treat
    // it as tier 2 only when GenericName is missing so apps that properly fill
    // both don't get double-counted.
    if (genericName.isEmpty() && containsAtWordBoundary(comment, query))
        return TierGeneric;

    for (const auto &kw : keywords) {
        if (kw.contains(query, Qt::CaseInsensitive))
            return TierKeyword;
    }

    // Categories share tier 3: typing "game" or "office" should pull in the
    // matching freedesktop category siblings (Game, ArcadeGame, OfficeApp …).
    // Plural queries also test the singularized form so "games" matches
    // "Game" / "ArcadeGame" — see singularize().
    const QString singularQuery = singularize(query);
    for (const auto &cat : categories) {
        if (cat.contains(query, Qt::CaseInsensitive))
            return TierKeyword;
        if (!singularQuery.isEmpty() && cat.contains(singularQuery, Qt::CaseInsensitive))
            return TierKeyword;
    }

    if (name.contains(query, Qt::CaseInsensitive))
        return TierNameMidword;

    return TierNoMatch;
}
}
