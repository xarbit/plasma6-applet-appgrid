/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "runnerfiltermodel.h"

#include "appmodel.h"

RunnerFilterModel::RunnerFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

void RunnerFilterModel::setAppModel(AppFilterModel *model)
{
    m_appModel = model;
    const auto refresh = [this]() {
        rebuildAppNameCache();
        invalidate();
    };
    connect(m_appModel, &QAbstractItemModel::modelReset, this, refresh);
    connect(m_appModel, &QAbstractItemModel::layoutChanged, this, refresh);
    connect(m_appModel, &QAbstractItemModel::rowsInserted, this, refresh);
    connect(m_appModel, &QAbstractItemModel::rowsRemoved, this, refresh);
    rebuildAppNameCache();
}

void RunnerFilterModel::rebuildAppNameCache()
{
    m_appNameCache.clear();
    if (!m_appModel)
        return;
    const int n = m_appModel->rowCount();
    m_appNameCache.reserve(n);
    for (int i = 0; i < n; ++i) {
        const auto name = m_appModel->index(i, 0).data(AppModel::NameRole).toString();
        if (!name.isEmpty())
            m_appNameCache.insert(name.toCaseFolded());
    }
}

bool RunnerFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!m_appModel)
        return true;

    const auto runnerName =
        sourceModel()->index(sourceRow, 0, sourceParent).data(Qt::DisplayRole).toString();
    return !m_appNameCache.contains(runnerName.toCaseFolded());
}
