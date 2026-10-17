/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "approwindex.h"

#include "appmodel.h"
#include "appsearch.h"

#include <QAbstractItemModel>

void AppRowIndex::setModel(const QAbstractItemModel *model)
{
    m_model = model;
    invalidate();
}

void AppRowIndex::invalidate()
{
    m_rows.clear();
    m_rowsBuilt = false;
    m_haystacks.clear();
}

void AppRowIndex::invalidateHaystacks()
{
    m_haystacks.clear();
}

int AppRowIndex::rowOf(const QString &storageId) const
{
    if (!m_rowsBuilt) {
        m_rows.clear();
        if (m_model) {
            const int count = m_model->rowCount();
            m_rows.reserve(count);
            for (int row = 0; row < count; ++row) {
                const QString sid = m_model->index(row, 0).data(AppModel::StorageIdRole).toString();
                if (!sid.isEmpty()) {
                    m_rows.insert(sid, row);
                }
            }
        }
        m_rowsBuilt = true;
    }
    return m_rows.value(storageId, -1);
}

QString AppRowIndex::haystack(int row) const
{
    const auto cached = m_haystacks.constFind(row);
    if (cached != m_haystacks.constEnd()) {
        return *cached;
    }
    if (!m_model) {
        return {};
    }
    return *m_haystacks.insert(row, AppSearch::haystack(m_model->index(row, 0)));
}
