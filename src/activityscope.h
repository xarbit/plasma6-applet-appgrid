/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

namespace KActivities
{
class Consumer;
}

/**
 * Which activity the favourites folders are scoped to: the current one with
 * per-activity favourites on, none (empty, shared folders) with them off.
 *
 * A just-constructed KActivities::Consumer has not synced with the activity
 * manager: its activities() / currentActivity() are bootstrap values (empty
 * or the null UUID). Acting on those would scope to the wrong activity and
 * prune the current one's folders, so nothing is reported until the service
 * runs; after that every switch is.
 */
class ActivityScope : public QObject
{
    Q_OBJECT

public:
    explicit ActivityScope(QObject *parent = nullptr);

    /** Scope to the current activity (per-activity favourites on). */
    void setEnabled(bool enabled);
    [[nodiscard]] bool isEnabled() const
    {
        return m_enabled;
    }

    /** The activity scoped to: the current one when enabled and known, else
     *  empty. */
    [[nodiscard]] QString activity() const;

Q_SIGNALS:
    /** The scope changed (or became known); @p activity as activity(). */
    void activityChanged(const QString &activity);
    /** The activities that exist, once known and on every change. */
    void activitiesChanged(const QStringList &activities);

private:
    [[nodiscard]] bool isKnown() const;
    void reportScope();

    KActivities::Consumer *const m_consumer;
    bool m_enabled = false;
};
