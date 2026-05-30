/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "frecencyprovider.h"

#include <PlasmaActivities/Stats/Query>
#include <PlasmaActivities/Stats/ResultModel>
#include <PlasmaActivities/Stats/Terms>

#include <QLoggingCategory>

#include <algorithm>

namespace KAStats = KActivities::Stats;
namespace KASTerms = KActivities::Stats::Terms;

// Opt-in via QT_LOGGING_RULES='appgrid.frecency.debug=true'. Used to triage
// storage-id mismatches between KAStats's resource URIs and the .desktop ids
// AppModel::StorageIdRole hands AppFilterModel.
Q_LOGGING_CATEGORY(lcFrecency, "appgrid.frecency", QtWarningMsg)

namespace
{
// Cap how many top-frecent apps we track. The ranking only needs enough rows
// to win tiebreaks among search hits, not the full launch history.
constexpr int kFrecencyLimit = 200;
const QLatin1String kAppPrefix("applications:");

QString storageIdFromResource(const QString &resource)
{
    if (resource.startsWith(kAppPrefix))
        return resource.mid(kAppPrefix.size());
    return {};
}
}

FrecencyProvider::FrecencyProvider(QObject *parent)
    : QObject(parent)
{
}

FrecencyProvider::~FrecencyProvider() = default;

void FrecencyProvider::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    if (!enabled) {
        teardownModel();
        return;
    }

    // Seed the chain with an explicit Query — the `Select | Order` overload
    // is not provided, so we cannot start the chain with two bare enums.
    const auto query = KAStats::Query(KASTerms::UsedResources) | KASTerms::HighScoredFirst | KASTerms::Agent::any() | KASTerms::Type::any()
        | KASTerms::Activity::any() | KASTerms::Url::startsWith(QStringLiteral("applications:")) | KASTerms::Limit(kFrecencyLimit);

    m_model = new KAStats::ResultModel(query, this);
    connect(m_model, &QAbstractItemModel::modelReset, this, &FrecencyProvider::rebuildScores);
    connect(m_model, &QAbstractItemModel::rowsInserted, this, &FrecencyProvider::rebuildScores);
    connect(m_model, &QAbstractItemModel::rowsRemoved, this, &FrecencyProvider::rebuildScores);
    connect(m_model, &QAbstractItemModel::dataChanged, this, &FrecencyProvider::rebuildScores);
    rebuildScores();
}

void FrecencyProvider::teardownModel()
{
    if (m_model) {
        m_model->deleteLater();
        m_model = nullptr;
    }
    if (!m_scores.isEmpty()) {
        m_scores.clear();
        Q_EMIT scoresChanged();
    }
}

void FrecencyProvider::rebuildScores()
{
    if (!m_model)
        return;

    const int rows = m_model->rowCount();
    QHash<QString, int> next;
    next.reserve(rows * 2);
    const QLatin1String kdePrefix("org.kde.");
    // Insert into the map keyed by `key`, but never demote an existing higher
    // score (matters when two distinct apps collide on the normalised form).
    const auto add = [&next](const QString &key, int score) {
        if (key.isEmpty())
            return;
        const auto it = next.find(key);
        if (it == next.end() || it.value() < score)
            next.insert(key, score);
    };
    for (int r = 0; r < rows; ++r) {
        const QModelIndex idx = m_model->index(r, 0);
        const QString resource = idx.data(KAStats::ResultModel::ResourceRole).toString();
        const QString sid = storageIdFromResource(resource);
        if (sid.isEmpty())
            continue;
        // Rank-based score (top row = `rows`, last row = 1) instead of the
        // raw KAStats score. Stable ordering even as absolute scores drift.
        const int score = rows - r;
        add(sid, score);
        // Same app, two common .desktop id shapes — different launchers /
        // KDE eras stored Konsole as both "org.kde.konsole.desktop" and
        // "konsole.desktop". AppModel::StorageIdRole may report either,
        // so index both spellings so the AppFilterModel lookup hits.
        if (sid.startsWith(kdePrefix))
            add(sid.mid(kdePrefix.size()), score);
        else
            add(kdePrefix + sid, score);
    }

    if (next != m_scores) {
        m_scores = next;
        if (lcFrecency().isDebugEnabled()) {
            QStringList sample = m_scores.keys();
            std::sort(sample.begin(), sample.end());
            if (sample.size() > 10)
                sample = sample.mid(0, 10);
            qCDebug(lcFrecency) << "scores populated:" << m_scores.size() << "keys; sample:" << sample;
        }
        Q_EMIT scoresChanged();
    }
}
