/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QSet>
#include <QString>

namespace KActivities
{
namespace Stats
{
class ResultModel;
}
}

/**
 * Always-on KActivities view of which applications have been used (have any
 * usage score). NewAppsTracker uses it to clear the "new app" badge: a recently
 * installed app the user has never launched is new; once launched it isn't.
 * AppGrid's own launch broadcasts (ResourceInstance::notifyAccessed) feed the
 * same database, so an app drops out of "new" the moment it is launched.
 */
class UsedAppsProvider : public QObject
{
    Q_OBJECT

public:
    explicit UsedAppsProvider(QObject *parent = nullptr);
    ~UsedAppsProvider() override;

    /** True once @p storageId has any recorded usage. */
    [[nodiscard]] bool isUsed(const QString &storageId) const
    {
        return m_used.contains(storageId);
    }

Q_SIGNALS:
    void usedAppsChanged();

private:
    void rebuild();

    KActivities::Stats::ResultModel *m_model = nullptr;
    QSet<QString> m_used;
};
