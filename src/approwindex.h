/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QPointer>
#include <QString>

class QAbstractItemModel;

/**
 * Lookups over the rows of an app model, built lazily and kept until the
 * model changes: the row of a storage id, and each row's search haystack
 * (AppSearch::haystack). The owner calls invalidate() when the model's rows
 * or their data change.
 */
class AppRowIndex
{
public:
    void setModel(const QAbstractItemModel *model);
    /** The rows changed: drop everything. */
    void invalidate();
    /** Row data changed, the rows did not: drop the haystacks. */
    void invalidateHaystacks();

    /** The row of @p storageId, or -1. */
    [[nodiscard]] int rowOf(const QString &storageId) const;
    [[nodiscard]] bool contains(const QString &storageId) const
    {
        return rowOf(storageId) >= 0;
    }
    /** AppSearch::haystack() of @p row. */
    [[nodiscard]] QString haystack(int row) const;

private:
    QPointer<const QAbstractItemModel> m_model;
    mutable QHash<QString, int> m_rows;
    mutable bool m_rowsBuilt = false;
    mutable QHash<int, QString> m_haystacks;
};
