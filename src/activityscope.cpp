/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "activityscope.h"

#include <PlasmaActivities/Consumer>

ActivityScope::ActivityScope(QObject *parent)
    : QObject(parent)
    , m_consumer(new KActivities::Consumer(this))
{
    connect(m_consumer, &KActivities::Consumer::serviceStatusChanged, this, [this](KActivities::Consumer::ServiceStatus status) {
        if (status == KActivities::Consumer::Running) {
            reportScope();
            Q_EMIT activitiesChanged(m_consumer->activities());
        }
    });
    connect(m_consumer, &KActivities::Consumer::currentActivityChanged, this, [this]() {
        if (m_enabled && isKnown()) {
            reportScope();
        }
    });
    connect(m_consumer, &KActivities::Consumer::activitiesChanged, this, [this](const QStringList &activities) {
        if (isKnown()) {
            Q_EMIT activitiesChanged(activities);
        }
    });
}

bool ActivityScope::isKnown() const
{
    return m_consumer->serviceStatus() == KActivities::Consumer::Running;
}

QString ActivityScope::activity() const
{
    return m_enabled && isKnown() ? m_consumer->currentActivity() : QString();
}

void ActivityScope::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    reportScope();
}

void ActivityScope::reportScope()
{
    Q_EMIT activityChanged(activity());
}
