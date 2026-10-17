/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "frecencyprovider.h"

#include "appgrid_frecency_debug.h"

#include "appurl.h"
#include "frecencyscoring.h"

#include <PlasmaActivities/Stats/Query>
#include <PlasmaActivities/Stats/ResultModel>
#include <PlasmaActivities/Stats/Terms>

#include <algorithm>

namespace KAStats = KActivities::Stats;
namespace KASTerms = KActivities::Stats::Terms;

namespace
{
// Cap how many top-frecent apps we track. The ranking only needs enough rows
// to win tiebreaks among search hits, not the full launch history.
constexpr int kFrecencyLimit = 200;
}

FrecencyProvider::FrecencyProvider(QObject *parent)
    : QObject(parent)
{
}

FrecencyProvider::~FrecencyProvider() = default;

void FrecencyProvider::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    if (!enabled) {
        teardownModel();
        return;
    }

    // Seed the chain with an explicit Query — the `Select | Order` overload
    // is not provided, so we cannot start the chain with two bare enums.
    const auto query = KAStats::Query(KASTerms::UsedResources) | KASTerms::HighScoredFirst | KASTerms::Agent::any() | KASTerms::Type::any()
        | KASTerms::Activity::any() | KASTerms::Url::startsWith(AppUrl::Scheme) | KASTerms::Limit(kFrecencyLimit);

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
    if (!m_model) {
        return;
    }

    const int rows = m_model->rowCount();
    QStringList resources;
    resources.reserve(rows);
    for (int r = 0; r < rows; ++r) {
        const QModelIndex idx = m_model->index(r, 0);
        resources.push_back(idx.data(KAStats::ResultModel::ResourceRole).toString());
    }
    const QHash<QString, int> next = FrecencyScoring::scoresFromResources(resources);

    if (next != m_scores) {
        m_scores = next;
        if (APPGRID_FRECENCY().isDebugEnabled()) {
            QStringList sample = m_scores.keys();
            std::sort(sample.begin(), sample.end());
            if (sample.size() > 10) {
                sample = sample.mid(0, 10);
            }
            qCDebug(APPGRID_FRECENCY) << "scores populated:" << m_scores.size() << "keys; sample:" << sample;
        }
        Q_EMIT scoresChanged();
    }
}
