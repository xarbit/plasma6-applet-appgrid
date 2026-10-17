/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QStringList>

/**
 * The favourites in their order, for AppFilterModel's favourites view and
 * search ranking: membership and position in O(1), rebuilt on each write
 * (QStringList::indexOf made a sort O(N²) per comparison).
 */
class FavoriteOrder
{
public:
    [[nodiscard]] const QStringList &list() const
    {
        return m_list;
    }
    /** Returns whether the favourites changed. */
    bool set(const QStringList &favorites)
    {
        if (m_list == favorites) {
            return false;
        }
        m_list = favorites;
        m_positions.clear();
        m_positions.reserve(favorites.size());
        for (int i = 0; i < favorites.size(); ++i) {
            m_positions.insert(favorites.at(i), i);
        }
        return true;
    }
    [[nodiscard]] bool contains(const QString &sid) const
    {
        return m_positions.contains(sid);
    }
    /** The position of @p sid, or @p fallback when it isn't a favourite. */
    [[nodiscard]] int position(const QString &sid, int fallback) const
    {
        return m_positions.value(sid, fallback);
    }

private:
    QStringList m_list;
    QHash<QString, int> m_positions;
};
