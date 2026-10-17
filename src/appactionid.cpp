/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appactionid.h"

#include "pluginhelpers.h"

#include <QUrlQuery>

namespace
{
const QLatin1String kActionKey{"action"};
}

namespace AppActionId
{
Parsed parse(const QString &id)
{
    QString rest = id;
    if (rest.startsWith(PluginHelpers::ApplicationsUrlPrefix)) {
        rest = rest.mid(PluginHelpers::ApplicationsUrlPrefix.size());
    }

    const int q = rest.indexOf(QLatin1Char('?'));
    if (q < 0) {
        return {rest, {}};
    }

    const QString storageId = rest.left(q);
    const QUrlQuery query(rest.mid(q + 1));
    return {storageId, query.queryItemValue(kActionKey)};
}

QString compose(const QString &storageId, const QString &actionName)
{
    return actionName.isEmpty() ? storageId : storageId + QLatin1Char('?') + kActionKey + QLatin1Char('=') + actionName;
}

bool hasAction(const QString &id)
{
    return !parse(id).actionName.isEmpty();
}

std::optional<KServiceAction> resolveAction(const KService::Ptr &service, const QString &actionName)
{
    if (!service || actionName.isEmpty()) {
        return std::nullopt;
    }
    const auto actions = service->actions();
    for (const KServiceAction &action : actions) {
        if (action.name() == actionName) {
            return action;
        }
    }
    return std::nullopt;
}
}
