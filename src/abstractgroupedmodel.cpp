/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "abstractgroupedmodel.h"

AbstractGroupedModel::AbstractGroupedModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AbstractGroupedModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant AbstractGroupedModel::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= m_rows.size()) {
        return {};
    }
    const Row &row = m_rows.at(index.row());
    switch (role) {
    case EntryTypeRole:
        return row.type;
    case FavoriteIdRole:
        return row.favoriteId;
    case FolderIdRole:
        return row.folderId;
    case FolderMembersRole:
        return row.members;
    case MemberCountRole:
        return row.members.size();
    case Qt::DisplayRole:
        return row.name;
    default:
        return {};
    }
}

QHash<int, QByteArray> AbstractGroupedModel::roleNames() const
{
    return {
        {EntryTypeRole, "entryType"},
        {FavoriteIdRole, "favoriteId"},
        {FolderIdRole, "folderId"},
        {FolderMembersRole, "folderMembers"},
        {MemberCountRole, "memberCount"},
        {Qt::DisplayRole, "display"},
    };
}

QStringList AbstractGroupedModel::folderMembers(const QString &folderId) const
{
    for (const Row &row : m_rows) {
        if (row.type == Folder && row.folderId == folderId) {
            return row.members;
        }
    }
    return {};
}

QString AbstractGroupedModel::folderName(const QString &folderId) const
{
    for (const Row &row : m_rows) {
        if (row.type == Folder && row.folderId == folderId) {
            return row.name;
        }
    }
    return {};
}

QString AbstractGroupedModel::folderOfMember(const QString &sid) const
{
    for (const Row &row : m_rows) {
        if (row.type == Folder && row.members.contains(sid)) {
            return row.folderId;
        }
    }
    return {};
}

int AbstractGroupedModel::entryTypeAt(int row) const
{
    return (row >= 0 && row < m_rows.size()) ? m_rows.at(row).type : App;
}

QString AbstractGroupedModel::folderIdAt(int row) const
{
    return (row >= 0 && row < m_rows.size()) ? m_rows.at(row).folderId : QString();
}

QString AbstractGroupedModel::favoriteIdAt(int row) const
{
    return (row >= 0 && row < m_rows.size()) ? m_rows.at(row).favoriteId : QString();
}

int AbstractGroupedModel::indexOfFolder(const QString &folderId) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).type == Folder && m_rows.at(i).folderId == folderId) {
            return i;
        }
    }
    return -1;
}

int AbstractGroupedModel::indexOfApp(const QString &favoriteId) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).type == App && m_rows.at(i).favoriteId == favoriteId) {
            return i;
        }
    }
    return -1;
}

void AbstractGroupedModel::setRows(const QList<Row> &rows)
{
    // A reset tears down every delegate, so skip it when nothing changed — a
    // KAStats push that doesn't move the visible rows must not flash the grid.
    if (rows == m_rows) {
        return;
    }
    beginResetModel();
    m_rows = rows;
    endResetModel();
}

void AbstractGroupedModel::moveRowAt(int from, int to)
{
    if (from < 0 || to < 0 || from >= m_rows.size() || to >= m_rows.size() || from == to) {
        return;
    }
    // beginMoveRows wants the destination *before* the row is taken out, so a
    // forward move passes to + 1.
    const int dest = to > from ? to + 1 : to;
    beginMoveRows({}, from, from, {}, dest);
    m_rows.move(from, to);
    endMoveRows();
}
