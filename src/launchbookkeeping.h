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
 * Per-user launch state, held by LaunchStateStore: the hidden and recent app
 * lists plus the launch counts, and the membership sets the filter and sort
 * hot paths consult. Owns the rebuild-on-write of those sets.
 *
 * Plain value type — no Qt model or signal coupling — so it's unit-testable
 * on its own. Mutating methods return whether state actually changed so the
 * store can decide whether to save and which signal to emit.
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
    void rebuildRecentSet();

    QStringList m_hidden;
    QStringList m_recent;
    QHash<QString, int> m_launchCounts;

    // Parallel-set lookups for the membership tests that hit every
    // filterAcceptsRow / lessThan call. Kept in sync on every write.
    QSet<QString> m_hiddenSet;
    QSet<QString> m_recentSet;
};
