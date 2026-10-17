/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "plasmoidservice.h"

#include "appgridplugin.h"

AppGridPlasmoidService::AppGridPlasmoidService(AppGridPlugin *plugin, QObject *parent)
    : QObject(parent)
    , m_plugin(plugin)
{
}

void AppGridPlasmoidService::requestAddToTaskManager(const QString &desktopFile)
{
    Q_EMIT addToTaskManagerRequested(desktopFile);
}

QString AppGridPlasmoidService::panelScreenName() const
{
    return m_plugin ? m_plugin->panelScreenName() : QString();
}

QVariantMap AppGridPlasmoidService::buttonAppearance() const
{
    return m_plugin ? m_plugin->buttonAppearance() : QVariantMap();
}

void AppGridPlasmoidService::setButtonAppearance(const QVariantMap &values)
{
    Q_EMIT setButtonAppearanceRequested(values);
}
