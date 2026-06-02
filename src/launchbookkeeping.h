/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>

/**
 * Per-user launch state for AppFilterModel: the hidden / favorite / recent /
 * known app lists plus their launch counts, and the derived membership sets
 * and favorite-position index that the filter and sort hot paths consult.
 * Owns the rebuild-on-write of those caches.
 *
 * Plain value type — no Qt model or signal coupling — so it's unit-testable
 * on its own. Mutating methods return whether state actually changed so the
 * model can decide when to invalidate and which Q_PROPERTY signal to emit.
 */
class LaunchBookkeeping
{
public:
    // -- Hidden --
    [[nodiscard]] const QStringList &hidden() const
    {
        return m_hidden;
    }
    bool setHidden(const QStringList &list);
    bool hide(const QString &sid); // append if new; false if empty/duplicate
    bool unhide(const QString &sid);
    [[nodiscard]] bool isHidden(const QString &sid) const
    {
        return !sid.isEmpty() && m_hiddenSet.contains(sid);
    }

    // -- Favorites --
    [[nodiscard]] const QStringList &favorites() const
    {
        return m_favorites;
    }
    bool setFavorites(const QStringList &list);
    [[nodiscard]] bool isFavorite(const QString &sid) const
    {
        return m_favoriteSet.contains(sid);
    }
    [[nodiscard]] int favoritePosition(const QString &sid, int fallback) const
    {
        return m_favoritePositions.value(sid, fallback);
    }

    // -- Recent --
    [[nodiscard]] const QStringList &recent() const
    {
        return m_recent;
    }
    bool setRecent(const QStringList &list);
    [[nodiscard]] bool isRecent(const QString &sid) const
    {
        return m_recentSet.contains(sid);
    }
    [[nodiscard]] bool hasRecent() const
    {
        return !m_recentSet.isEmpty();
    }
    bool recordRecent(const QString &sid, int maxRecent); // prepend + cap

    // -- Known (drives the new-app badge) --
    [[nodiscard]] const QStringList &known() const
    {
        return m_known;
    }
    bool setKnown(const QStringList &list);
    [[nodiscard]] bool isNew(const QString &sid) const
    {
        return !m_knownSet.isEmpty() && !m_knownSet.contains(sid);
    }
    bool addKnown(const QString &sid); // false if already known

    // -- Launch counts --
    [[nodiscard]] QVariantMap launchCountsMap() const;
    bool setLaunchCountsFromMap(const QVariantMap &map); // true if changed
    [[nodiscard]] const QHash<QString, int> &launchCounts() const
    {
        return m_launchCounts;
    }
    [[nodiscard]] int launchCount(const QString &sid) const
    {
        return m_launchCounts.value(sid, 0);
    }
    void bumpLaunch(const QString &sid)
    {
        m_launchCounts[sid] = m_launchCounts.value(sid, 0) + 1;
    }

private:
    void rebuildHiddenSet();
    void rebuildFavoriteSet();
    void rebuildRecentSet();
    void rebuildKnownSet();

    QStringList m_hidden;
    QStringList m_favorites;
    QStringList m_recent;
    QStringList m_known;
    QHash<QString, int> m_launchCounts;

    // Parallel-set lookups for the membership tests that hit every
    // filterAcceptsRow / lessThan call. Kept in sync on every write.
    QSet<QString> m_hiddenSet;
    QSet<QString> m_favoriteSet;
    QSet<QString> m_recentSet;
    QSet<QString> m_knownSet;
    // Position lookup for favorites sort — O(1) replacement for QStringList
    // indexOf that made lessThan O(N²) per comparison.
    QHash<QString, int> m_favoritePositions;
};
