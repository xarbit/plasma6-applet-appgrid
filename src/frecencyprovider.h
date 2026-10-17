/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QObject>
#include <QString>

namespace KActivities
{
namespace Stats
{
class ResultModel;
}
}

/**
 * Pulls a frecency-ranked (frequency + recency) list of recently-launched apps
 * from KActivities and exposes it as a storageId → integer rank map. Higher
 * map value = better rank (top of the KAStats list = the largest score).
 *
 * Opt-in: idle until setEnabled(true) — there is no KAStats traffic and the
 * map stays empty for users who have not turned the search frecency bias on.
 * Read-only with respect to KActivities; AppGrid's launch broadcasts already
 * feed the database (see #95 close-out / LaunchService::launch).
 */
class FrecencyProvider : public QObject
{
    Q_OBJECT

public:
    explicit FrecencyProvider(QObject *parent = nullptr);
    ~FrecencyProvider() override;

    [[nodiscard]] bool isEnabled() const
    {
        return m_enabled;
    }
    void setEnabled(bool enabled);

    [[nodiscard]] QHash<QString, int> scores() const
    {
        return m_scores;
    }

Q_SIGNALS:
    void scoresChanged();

private:
    void rebuildScores();
    void teardownModel();

    bool m_enabled = false;
    KActivities::Stats::ResultModel *m_model = nullptr;
    QHash<QString, int> m_scores;
};
