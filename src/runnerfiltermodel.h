/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>

#include "appfiltermodel.h"
#include "filterproxymodel.h"

/**
 * @brief Proxy that filters KRunner results already present in AppFilterModel.
 *
 * Hides runner rows whose display name matches a visible app name (case
 * insensitive) so the unified search view doesn't show a row twice. The
 * app-name cache is rebuilt lazily: app-model changes only mark it dirty, and
 * the O(app-count) rebuild happens at most once, on the next filter pass that
 * actually needs it (skipped entirely when there are no runner rows).
 */
class RunnerFilterModel : public FilterProxyModel
{
    Q_OBJECT
public:
    explicit RunnerFilterModel(QObject *parent = nullptr);
    void setAppModel(AppFilterModel *model);
    void setSourceModel(QAbstractItemModel *model) override;

    /** True if the result at proxy @p row is a jump-list action — its match data
     *  carries "?action=" — rather than a plain app or file. The unified view
     *  routes these to the runner context menu so the ACTION (not the parent app)
     *  is favourited, even though the row resolves the app's storage id. */
    [[nodiscard]] bool rowIsAction(int row) const;

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    void ensureAppNameCache() const;
    void captureSourceRoles();
    [[nodiscard]] QString storageIdFromRow(const QModelIndex &idx) const;

    AppFilterModel *m_appModel = nullptr;
    // Folded names of the currently-visible apps, for the runner de-dup.
    // Mutable + dirty-flagged so the rebuild is lazy (see ensureAppNameCache).
    mutable QSet<QString> m_appNameCache;
    mutable bool m_appNameCacheDirty = true;
    // Role index of KRunner ResultsModel's "urls" role — captured on
    // setSourceModel so storageIdFromRow doesn't loop roleNames() per
    // call. -1 until a source is attached.
    int m_urlsRole = -1;
};
