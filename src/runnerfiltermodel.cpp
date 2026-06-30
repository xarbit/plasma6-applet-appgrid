/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "runnerfiltermodel.h"

#include "appactionid.h"
#include "appmodel.h"
#include "pluginhelpers.h"

#include <KRunner/QueryMatch>
#include <KRunner/ResultsModel>

#include <QUrl>

RunnerFilterModel::RunnerFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

void RunnerFilterModel::setAppModel(AppFilterModel *model)
{
    m_appModel = model;
    // App-model changes only mark the name cache dirty + re-filter; the
    // O(app-count) rebuild is deferred to the next filter pass that needs it
    // (ensureAppNameCache), coalescing the burst of signals one keystroke emits.
    const auto markDirty = [this]() {
        m_appNameCacheDirty = true;
        invalidate();
    };
    connect(m_appModel, &QAbstractItemModel::modelReset, this, markDirty);
    connect(m_appModel, &QAbstractItemModel::layoutChanged, this, markDirty);
    connect(m_appModel, &QAbstractItemModel::rowsInserted, this, markDirty);
    connect(m_appModel, &QAbstractItemModel::rowsRemoved, this, markDirty);
    // Hidden-set + searchShowsHidden control whether KRunner-served
    // hidden apps drop out — same gate AppFilterModel applies on its
    // own rows.
    connect(m_appModel, &AppFilterModel::hiddenAppsChanged, this, &RunnerFilterModel::invalidate);
    connect(m_appModel, &AppFilterModel::searchShowsHiddenChanged, this, &RunnerFilterModel::invalidate);
    m_appNameCacheDirty = true;
}

void RunnerFilterModel::setSourceModel(QAbstractItemModel *model)
{
    QSortFilterProxyModel::setSourceModel(model);
    captureSourceRoles();
}

bool RunnerFilterModel::rowIsAction(int row) const
{
    auto *results = qobject_cast<KRunner::ResultsModel *>(sourceModel());
    if (!results || row < 0 || row >= rowCount()) {
        return false;
    }
    const QModelIndex sourceIdx = mapToSource(index(row, 0));
    return AppActionId::hasAction(results->getQueryMatch(sourceIdx).data().toUrl().toString());
}

void RunnerFilterModel::captureSourceRoles()
{
    if (!sourceModel()) {
        m_urlsRole = -1;
        return;
    }
    m_urlsRole = sourceModel()->roleNames().key(QByteArrayLiteral("urls"), -1);
}

void RunnerFilterModel::ensureAppNameCache() const
{
    if (!m_appNameCacheDirty) {
        return;
    }
    m_appNameCache.clear();
    if (m_appModel) {
        const int n = m_appModel->rowCount();
        m_appNameCache.reserve(n);
        for (int i = 0; i < n; ++i) {
            const auto name = m_appModel->index(i, 0).data(AppModel::NameRole).toString();
            if (!name.isEmpty()) {
                m_appNameCache.insert(name.toCaseFolded());
            }
        }
    }
    m_appNameCacheDirty = false;
}

QString RunnerFilterModel::storageIdFromRow(const QModelIndex &idx) const
{
    if (m_urlsRole < 0) {
        return {};
    }
    return PluginHelpers::runnerStorageId(idx.data(m_urlsRole));
}

bool RunnerFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!m_appModel) {
        return true;
    }

    const auto idx = sourceModel()->index(sourceRow, 0, sourceParent);

    // Dedup against visible app names so the unified view doesn't show
    // the same app twice (once via AppFilterModel, once via KRunner's
    // services runner). The name cache is rebuilt here lazily on first use
    // after an app-model change.
    ensureAppNameCache();
    const auto runnerName = idx.data(Qt::DisplayRole).toString();
    if (m_appNameCache.contains(runnerName.toCaseFolded())) {
        return false;
    }

    // Hidden-app filter — mirrors AppFilterModel: hidden rows drop out
    // unless searchShowsHidden is on (the default). Without this,
    // toggling the knob off would still leak hidden apps via the
    // services runner's row for the same .desktop file.
    if (!m_appModel->searchShowsHidden()) {
        const auto sid = storageIdFromRow(idx);
        if (!sid.isEmpty() && m_appModel->isHidden(sid)) {
            return false;
        }
    }

    return true;
}
