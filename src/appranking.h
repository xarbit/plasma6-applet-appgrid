/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "favoriteorder.h"
#include "searchranking.h"

#include <QHash>
#include <QModelIndex>
#include <QSet>
#include <QString>
#include <QStringList>

class LaunchBookkeeping;

/**
 * The order AppFilterModel sorts its rows in: the favourites in their own
 * order, search results by relevance (SearchRanking), otherwise by name,
 * launch count or category. Holds what ranks the apps besides the rows
 * themselves (favourites, default and preferred apps, frecency) and a cache
 * of each row's sort inputs, so a re-sort per keystroke compares cached
 * integers and short strings instead of re-reading and re-folding roles.
 */
class AppRanking
{
public:
    enum SortMode {
        Alphabetical = 0,
        MostUsed = 1,
        ByCategory = 2,
    };

    // What orders the rows now, from the model's view state.
    struct Order {
        // The search; non-empty ranks by relevance.
        QString query;
        bool favoritesOnly = false;
        bool favoritesAlphabetical = false;
        int sortMode = Alphabetical;
    };

    // The inputs. Each returns whether it changed; a change that affects the
    // cached row inputs drops them.
    bool setFavorites(const QStringList &favorites);
    [[nodiscard]] const FavoriteOrder &favorites() const
    {
        return m_favorites;
    }
    bool setDefaultApps(const QStringList &apps);
    [[nodiscard]] const QStringList &defaultApps() const
    {
        return m_defaultApps;
    }
    bool setPreferredApps(const QSet<QString> &apps);
    bool setFrecencyScores(const QHash<QString, int> &scores);
    bool setUseFrecency(bool use);
    [[nodiscard]] bool useFrecency() const
    {
        return m_useFrecency;
    }

    /** Drop the cached row inputs: the query, the launch counts or the rows
     *  changed. */
    void invalidate();

    /** Whether the source row @p left sorts before @p right. */
    [[nodiscard]] bool lessThan(const QModelIndex &left, const QModelIndex &right, const Order &order, const LaunchBookkeeping &book) const;

private:
    struct RowScore {
        QString sid;
        QString name;
        QString category;
        int relevance = SearchRanking::TierNoMatch;
        int launchCount = 0;
        bool isDefault = false; // a mimeapps.list default for some type
        bool isPreferred = false; // a role default (browser/mail/file-mgr/terminal) — ranks above isDefault
        bool isFavorite = false; // starred in AppGrid's favourites — ranks above isPreferred
    };
    // By value, not by reference: the cache is a QHash and a later insert can
    // rehash it (was issue #202). The contents are implicitly shared QStrings
    // and scalars, so the copy is cheap.
    [[nodiscard]] RowScore rowScore(const QModelIndex &sourceIndex, const QString &query, const LaunchBookkeeping &book) const;

    FavoriteOrder m_favorites;
    QStringList m_defaultApps;
    QSet<QString> m_defaultSet;
    // The role defaults (browser / mail / file manager via KApplicationTrader,
    // terminal via kdeglobals); they outrank the mimeapps defaults.
    QSet<QString> m_preferred;
    QHash<QString, int> m_frecency;
    // Substitute the frecency scores for the launch counts in search ranking.
    bool m_useFrecency = false;
    // Source row → cached sort inputs. lessThan() is handed source indices,
    // and the source row is stable across a re-sort, so sorting alone never
    // drops them.
    mutable QHash<int, RowScore> m_cache;
};
