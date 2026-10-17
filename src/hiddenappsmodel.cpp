/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "hiddenappsmodel.h"

HiddenAppsModel::HiddenAppsModel(QObject *parent)
    : AppIdsModel(parent)
{
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

QVariant HiddenAppsModel::data(const QModelIndex &index, int role) const
{
    if (role == NameRole) {
        // An uninstalled app has no name left; show its id.
        const QString name = AppIdsModel::data(index, NameRole).toString();
        return name.isEmpty() ? AppIdsModel::data(index, StorageIdRole) : name;
    }
    return AppIdsModel::data(index, role);
}

void HiddenAppsModel::setFilter(const QString &text)
{
    if (m_filter == text) {
        return;
    }
    m_filter = text;
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

void HiddenAppsModel::appsChanged()
{
    // A filter by name may now match differently.
    rebuild();
    AppIdsModel::appsChanged();
}

void HiddenAppsModel::rebuild()
{
    QStringList ids;
    const QStringList hidden = m_state ? m_state->hiddenApps() : QStringList();
    for (const QString &sid : hidden) {
        if (m_filter.isEmpty() || sid.contains(m_filter, Qt::CaseInsensitive) || fields().fields(sid).name.contains(m_filter, Qt::CaseInsensitive)) {
            ids.append(sid);
        }
    }
    setIds(ids);
}
