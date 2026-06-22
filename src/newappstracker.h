/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KSharedConfig>

#include <QDate>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QStringList>

class UsedAppsProvider;

/**
 * @brief Tracks which installed apps are "newly installed" for the new-app badge.
 *
 * Mirrors Kickoff (plasma-workspace RootModel::refreshNewlyInstalledApps): a
 * persisted baseline of every app ever seen plus a per-app FirstSeen date.
 * refresh() diffs the current install set against the baseline — an id absent
 * from a non-empty baseline is genuinely new and gets FirstSeen=today. The very
 * first run seeds the baseline with everything installed, so nothing flashes new.
 *
 * An app is new while FirstSeen is within the window AND it has no recorded
 * KActivities usage (UsedAppsProvider). Launching it (which AppGrid broadcasts
 * to KActivities) drops it from the used-set's complement, clearing the badge
 * before the window even lapses — exactly Kickoff's resource-score clear.
 *
 * State lives in its own config file (appgridstaterc), never the shared
 * appgridrc: it is recomputed locally on every KSycoca change, and keeping its
 * sync off appgridrc means it can't trip the launch-state KConfigWatcher.
 */
class NewAppsTracker : public QObject
{
    Q_OBJECT
public:
    /** @p config defaults to appgridstaterc; injectable so tests can use a scratch file. */
    explicit NewAppsTracker(UsedAppsProvider *usedApps, const KSharedConfig::Ptr &config = {}, QObject *parent = nullptr);

    /** Diff @p installedIds against the stored baseline, stamp newly-installed
     *  apps, prune the uninstalled/expired, and recompute the new-app set. */
    void refresh(const QStringList &installedIds);

    [[nodiscard]] QSet<QString> newApps() const
    {
        return m_new;
    }

Q_SIGNALS:
    void newAppsChanged();

private:
    // Rebuild m_new from m_firstSeen minus the KActivities-used apps; emit on change.
    void recompute();

    UsedAppsProvider *m_usedApps = nullptr;
    KSharedConfig::Ptr m_config;
    QHash<QString, QDate> m_firstSeen; // storageId → first time we saw it installed
    QSet<QString> m_new;
};
