/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appidsmodel.h"

#include <KSycoca>

AppIdsModel::AppIdsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, [this]() {
        m_fields.clear();
        appsChanged();
    });
}

int AppIdsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_ids.size());
}

QVariant AppIdsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_ids.size()) {
        return {};
    }
    const QString &id = m_ids.at(index.row());
    if (role == StorageIdRole) {
        return id;
    }
    const AppFieldsCache::Fields f = m_fields.fields(id);
    switch (role) {
    case NameRole:
        return f.name;
    case IconNameRole:
        return f.icon;
    case GenericNameRole:
        return f.genericName;
    case CommentRole:
        return f.comment;
    case DesktopFileRole:
        return f.desktopFile;
    case InstallSourceRole:
        return f.installSource;
    default:
        return {};
    }
}

QHash<int, QByteArray> AppIdsModel::roleNames() const
{
    return {
        {StorageIdRole, "storageId"},
        {NameRole, "name"},
        {IconNameRole, "iconName"},
        {GenericNameRole, "genericName"},
        {CommentRole, "comment"},
        {DesktopFileRole, "desktopFile"},
        {InstallSourceRole, "installSource"},
    };
}

void AppIdsModel::setIds(const QStringList &ids)
{
    if (ids != m_ids) {
        beginResetModel();
        m_ids = ids;
        endResetModel();
    }
    Q_EMIT countChanged();
}

void AppIdsModel::appsChanged()
{
    if (!m_ids.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(int(m_ids.size()) - 1));
    }
}
