/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>
#include <QSortFilterProxyModel>

#include "appfiltermodel.h"

/**
 * @brief Proxy that filters KRunner results already present in AppFilterModel.
 *
 * Hides runner rows whose display name matches a visible app name (case
 * insensitive) so the unified search view doesn't show a row twice. The
 * app-name cache rebuilds on every source-model change so lookups stay
 * O(1) per row instead of O(app-count).
 */
class RunnerFilterModel : public QSortFilterProxyModel {
    Q_OBJECT
public:
    explicit RunnerFilterModel(QObject *parent = nullptr);
    void setAppModel(AppFilterModel *model);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    void rebuildAppNameCache();

    AppFilterModel *m_appModel = nullptr;
    QSet<QString> m_appNameCache;
};
