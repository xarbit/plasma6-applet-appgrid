/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appidsmodel.h"
#include "launchstatestore.h"

#include <QPointer>

/**
 * The recently launched apps, most recent first, for the recents row: one row
 * per app with its fields, following the launch state store live. A QML type
 * each recents row creates, given the controller's store.
 */
class RecentAppsModel : public AppIdsModel
{
    Q_OBJECT
    Q_PROPERTY(LaunchStateStore *launchState READ launchState WRITE setLaunchState NOTIFY launchStateChanged)

public:
    explicit RecentAppsModel(QObject *parent = nullptr);

    [[nodiscard]] LaunchStateStore *launchState() const
    {
        return m_state.data();
    }
    void setLaunchState(LaunchStateStore *state);

Q_SIGNALS:
    void launchStateChanged();

private:
    QPointer<LaunchStateStore> m_state;
};
