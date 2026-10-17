/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "hiddenappsmodel.h"

#include "launchstatestore.h"

#include <KSycoca>

HiddenAppsModel::HiddenAppsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, [this]() {
        m_fields.clear();
        rebuild();
    });
}

void HiddenAppsModel::setLaunchState(LaunchStateStore *state)
{
    if (m_state == state) {
        return;
    }
    if (m_state) {
        disconnect(m_state, nullptr, this, nullptr);
    }
    m_state = state;
    if (m_state) {
        connect(m_state, &LaunchStateStore::hiddenAppsChanged, this, &HiddenAppsModel::rebuild);
    }
    rebuild();
    Q_EMIT launchStateChanged();
}

int HiddenAppsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant HiddenAppsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size()) {
        return {};
    }
    const QString &sid = m_rows.at(index.row());
    switch (role) {
    case StorageIdRole:
        return sid;
    case NameRole: {
        // An uninstalled app has no name left; show its id.
        const QString name = m_fields.fields(sid).name;
        return name.isEmpty() ? sid : name;
    }
    case IconNameRole:
        return m_fields.fields(sid).icon;
    case GenericNameRole:
        return m_fields.fields(sid).genericName;
    default:
        return {};
    }
}

QHash<int, QByteArray> HiddenAppsModel::roleNames() const
{
    return {
        {StorageIdRole, "storageId"},
        {NameRole, "name"},
        {IconNameRole, "iconName"},
        {GenericNameRole, "genericName"},
    };
}

void HiddenAppsModel::setFilter(const QString &filter)
{
    if (m_filter == filter) {
        return;
    }
    m_filter = filter;
    rebuild();
    Q_EMIT filterChanged();
}

bool HiddenAppsModel::isEmpty() const
{
    return !m_state || m_state->hiddenApps().isEmpty();
}

void HiddenAppsModel::unhide(const QString &storageId)
{
    if (m_state) {
        m_state->unhide(storageId);
    }
}

void HiddenAppsModel::unhideAll()
{
    if (m_state) {
        m_state->setHiddenApps({});
    }
}

void HiddenAppsModel::rebuild()
{
    QStringList rows;
    const QStringList hidden = m_state ? m_state->hiddenApps() : QStringList();
    for (const QString &sid : hidden) {
        if (m_filter.isEmpty() || sid.contains(m_filter, Qt::CaseInsensitive) || m_fields.fields(sid).name.contains(m_filter, Qt::CaseInsensitive)) {
            rows.append(sid);
        }
    }
    if (rows != m_rows) {
        beginResetModel();
        m_rows = rows;
        endResetModel();
    }
    // Also when only filtered-out apps changed: empty may have.
    Q_EMIT countChanged();
}
