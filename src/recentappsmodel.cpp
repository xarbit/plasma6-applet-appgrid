/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "recentappsmodel.h"

RecentAppsModel::RecentAppsModel(QObject *parent)
    : AppIdsModel(parent)
{
}

void RecentAppsModel::setLaunchState(LaunchStateStore *state)
{
    if (m_state == state) {
        return;
    }
    if (m_state) {
        disconnect(m_state, nullptr, this, nullptr);
    }
    m_state = state;
    if (m_state) {
        connect(m_state, &LaunchStateStore::recentAppsChanged, this, [this]() {
            setIds(m_state->recentApps());
        });
    }
    setIds(m_state ? m_state->recentApps() : QStringList());
    Q_EMIT launchStateChanged();
}
