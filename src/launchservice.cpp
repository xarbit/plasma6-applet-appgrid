/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "launchservice.h"

#include "appactionid.h"
#include "appgridconstants.h"
#include "applauncher.h"
#include "appresolver.h"
#include "appurl.h"
#include "favoriteid.h"

#include <PlasmaActivities/ResourceInstance>
#include <QUrl>
#include <QVariantMap>

LaunchService::LaunchService(QObject *parent)
    : QObject(parent)
{
}

QString LaunchService::launchKey(const QString &id)
{
    if (id.isEmpty() || FavoriteId::isDocument(id)) {
        return {};
    }
    const AppActionId::Parsed parsed = AppActionId::parse(id);
    return AppActionId::compose(parsed.storageId, parsed.actionName);
}

bool LaunchService::launch(const QString &id)
{
    const AppResolver::Target target = AppResolver::resolve(id);
    if (!target.isValid()) {
        return false;
    }
    if (!target.service) {
        AppLauncher::open(target.documentUrl);
        return true;
    }
    if (target.action) {
        AppLauncher::launch(*target.action);
    } else {
        AppLauncher::launch(target.service);
    }
    const QString key = launchKey(id);
    // The convention Kicker, Kickoff and friends use: the resource is
    // "applications:<id>", tagged with our agent so tools can attribute the
    // launch to AppGrid.
    KActivities::ResourceInstance::notifyAccessed(QUrl(AppUrl::Scheme + key), QString(AppGrid::ApplicationId));
    Q_EMIT appLaunched(key);
    return true;
}

bool LaunchService::launchAction(const QString &storageId, const QString &actionName)
{
    if (storageId.isEmpty() || actionName.isEmpty()) {
        return false;
    }
    return launch(AppActionId::compose(AppActionId::parse(storageId).storageId, actionName));
}

QVariantList LaunchService::appActions(const QString &storageId) const
{
    QVariantList result;
    const auto actions = AppResolver::actions(AppResolver::resolve(AppActionId::parse(storageId).storageId).service);
    for (const KServiceAction &action : actions) {
        result.append(QVariantMap{
            {QStringLiteral("text"), action.text()},
            {QStringLiteral("icon"), action.icon()},
            {QStringLiteral("name"), action.name()},
        });
    }
    return result;
}
