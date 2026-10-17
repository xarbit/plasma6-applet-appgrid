/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appranking.h"

#include "appmodel.h"
#include "appsearch.h"
#include "launchbookkeeping.h"

#include <limits>

bool AppRanking::setFavorites(const QStringList &favorites)
{
    if (!m_favorites.set(favorites)) {
        return false;
    }
    invalidate();
    return true;
}

bool AppRanking::setDefaultApps(const QStringList &apps)
{
    if (m_defaultApps == apps) {
        return false;
    }
    m_defaultApps = apps;
    m_defaultSet = QSet<QString>(apps.cbegin(), apps.cend());
    invalidate();
    return true;
}

bool AppRanking::setPreferredApps(const QSet<QString> &apps)
{
    if (m_preferred == apps) {
        return false;
    }
    m_preferred = apps;
    invalidate();
    return true;
}

bool AppRanking::setFrecencyScores(const QHash<QString, int> &scores)
{
    if (m_frecency == scores) {
        return false;
    }
    m_frecency = scores;
    return true;
}

bool AppRanking::setUseFrecency(bool use)
{
    if (m_useFrecency == use) {
        return false;
    }
    m_useFrecency = use;
    return true;
}

void AppRanking::invalidate()
{
    m_cache.clear();
}

AppRanking::RowScore AppRanking::rowScore(const QModelIndex &sourceIndex, const QString &query, const LaunchBookkeeping &book) const
{
    const int sourceRow = sourceIndex.row();
    const auto cached = m_cache.constFind(sourceRow);
    if (cached != m_cache.constEnd()) {
        return *cached;
    }

    RowScore s;
    s.sid = sourceIndex.data(AppModel::StorageIdRole).toString();
    s.name = sourceIndex.data(AppModel::NameRole).toString();
    s.category = sourceIndex.data(AppModel::CategoryRole).toString();
    s.launchCount = book.launchCount(s.sid);
    s.isDefault = m_defaultSet.contains(s.sid);
    s.isPreferred = m_preferred.contains(s.sid);
    s.isFavorite = m_favorites.contains(s.sid);
    // Relevance only matters while searching; skip its role reads + case-folds
    // in the alphabetical / most-used / by-category sort modes.
    if (!query.isEmpty()) {
        s.relevance = AppSearch::relevance(sourceIndex, query);
    }
    return *m_cache.insert(sourceRow, s);
}

bool AppRanking::lessThan(const QModelIndex &left, const QModelIndex &right, const Order &order, const LaunchBookkeeping &book) const
{
    const RowScore l = rowScore(left, order.query, book);
    const RowScore r = rowScore(right, order.query, book);

    // The favourites view keeps the favourites' own order, unless the user
    // opted into alphabetical.
    if (order.favoritesOnly) {
        if (order.favoritesAlphabetical) {
            return QString::localeAwareCompare(l.name, r.name) < 0;
        }
        // A sid missing from the favourites sorts after every real entry.
        constexpr int kSortToEnd = std::numeric_limits<int>::max();
        return m_favorites.position(l.sid, kSortToEnd) < m_favorites.position(r.sid, kSortToEnd);
    }

    // When searching, rank by match relevance first (SearchRanking::compare);
    // a tie falls through to the name below.
    if (!order.query.isEmpty()) {
        // Frecency (when opted in) stands in for the launch count everywhere
        // the search ranking reads it. Looked up per comparison by the cached
        // sid, so it stays live without being cached itself.
        const bool frecency = m_useFrecency && !m_frecency.isEmpty();
        const auto rank = [&](const RowScore &s) {
            return SearchRanking::ResultRank{s.relevance, frecency ? m_frecency.value(s.sid, 0) : s.launchCount, s.isFavorite, s.isPreferred, s.isDefault};
        };
        if (const int result = SearchRanking::compare(rank(l), rank(r)); result != 0) {
            return result < 0;
        }
    } else if (order.sortMode == MostUsed) {
        if (l.launchCount != r.launchCount) {
            return l.launchCount > r.launchCount;
        }
    } else if (order.sortMode == ByCategory) {
        const int cmp = QString::localeAwareCompare(l.category, r.category);
        if (cmp != 0) {
            return cmp < 0;
        }
    }

    return QString::localeAwareCompare(l.name, r.name) < 0;
}
