/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "usedappsprovider.h"

#include "pluginhelpers.h"

#include <PlasmaActivities/Stats/Query>
#include <PlasmaActivities/Stats/ResultModel>
#include <PlasmaActivities/Stats/Terms>

namespace KAStats = KActivities::Stats;
namespace KASTerms = KActivities::Stats::Terms;

namespace
{
// Presence, not ranking — the badge only needs "has this been used at all".
// Well above any real launch history.
constexpr int kUsedAppsLimit = 1000;
}

UsedAppsProvider::UsedAppsProvider(QObject *parent)
    : QObject(parent)
{
    const auto query = KAStats::Query(KASTerms::UsedResources) | KASTerms::Agent::any() | KASTerms::Type::any() | KASTerms::Activity::any()
        | KASTerms::Url::startsWith(PluginHelpers::ApplicationsUrlPrefix) | KASTerms::Limit(kUsedAppsLimit);

    m_model = new KAStats::ResultModel(query, this);
    connect(m_model, &QAbstractItemModel::modelReset, this, &UsedAppsProvider::rebuild);
    connect(m_model, &QAbstractItemModel::rowsInserted, this, &UsedAppsProvider::rebuild);
    connect(m_model, &QAbstractItemModel::rowsRemoved, this, &UsedAppsProvider::rebuild);
    rebuild();
}

UsedAppsProvider::~UsedAppsProvider() = default;

void UsedAppsProvider::rebuild()
{
    QSet<QString> next;
    const int rows = m_model->rowCount();
    next.reserve(rows);
    for (int r = 0; r < rows; ++r) {
        QString resource = PluginHelpers::stripApplicationsPrefix(m_model->index(r, 0).data(KAStats::ResultModel::ResourceRole).toString());
        // An action launch (foo.desktop?action=x) still counts the base app as used.
        const int query = resource.indexOf(QLatin1Char('?'));
        if (query >= 0) {
            resource = resource.left(query);
        }
        if (!resource.isEmpty()) {
            next.insert(resource);
        }
    }
    if (next != m_used) {
        m_used = next;
        Q_EMIT usedAppsChanged();
    }
}
