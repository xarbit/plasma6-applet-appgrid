/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "launchbookkeeping.h"

void LaunchBookkeeping::rebuildHiddenSet()
{
    m_hiddenSet = QSet<QString>(m_hidden.cbegin(), m_hidden.cend());
}

void LaunchBookkeeping::rebuildFavoriteSet()
{
    m_favoriteSet = QSet<QString>(m_favorites.cbegin(), m_favorites.cend());
    m_favoritePositions.clear();
    m_favoritePositions.reserve(m_favorites.size());
    for (int i = 0; i < m_favorites.size(); ++i)
        m_favoritePositions.insert(m_favorites.at(i), i);
}

void LaunchBookkeeping::rebuildRecentSet()
{
    m_recentSet = QSet<QString>(m_recent.cbegin(), m_recent.cend());
}

void LaunchBookkeeping::rebuildKnownSet()
{
    m_knownSet = QSet<QString>(m_known.cbegin(), m_known.cend());
}

bool LaunchBookkeeping::setHidden(const QStringList &list)
{
    if (m_hidden == list)
        return false;
    m_hidden = list;
    rebuildHiddenSet();
    return true;
}

bool LaunchBookkeeping::hide(const QString &sid)
{
    if (sid.isEmpty() || m_hiddenSet.contains(sid))
        return false;
    m_hidden.append(sid);
    m_hiddenSet.insert(sid);
    return true;
}

bool LaunchBookkeeping::unhide(const QString &sid)
{
    if (!m_hiddenSet.remove(sid))
        return false;
    m_hidden.removeAll(sid);
    return true;
}

bool LaunchBookkeeping::setFavorites(const QStringList &list)
{
    if (m_favorites == list)
        return false;
    m_favorites = list;
    rebuildFavoriteSet();
    return true;
}

bool LaunchBookkeeping::setRecent(const QStringList &list)
{
    if (m_recent == list)
        return false;
    m_recent = list;
    rebuildRecentSet();
    return true;
}

bool LaunchBookkeeping::recordRecent(const QString &sid, int maxRecent)
{
    if (sid.isEmpty())
        return false;
    m_recent.removeAll(sid);
    m_recent.prepend(sid);
    while (m_recent.size() > maxRecent)
        m_recent.removeLast();
    rebuildRecentSet();
    return true;
}

bool LaunchBookkeeping::setKnown(const QStringList &list)
{
    if (m_known == list)
        return false;
    m_known = list;
    rebuildKnownSet();
    return true;
}

bool LaunchBookkeeping::addKnown(const QString &sid)
{
    if (m_knownSet.contains(sid))
        return false;
    m_known.append(sid);
    m_knownSet.insert(sid);
    return true;
}

QVariantMap LaunchBookkeeping::launchCountsMap() const
{
    QVariantMap map;
    for (auto it = m_launchCounts.cbegin(); it != m_launchCounts.cend(); ++it)
        map.insert(it.key(), it.value());
    return map;
}

bool LaunchBookkeeping::setLaunchCountsFromMap(const QVariantMap &map)
{
    QHash<QString, int> next;
    next.reserve(map.size());
    for (auto it = map.cbegin(); it != map.cend(); ++it)
        next.insert(it.key(), it.value().toInt());
    if (next == m_launchCounts)
        return false;
    m_launchCounts = next;
    return true;
}
