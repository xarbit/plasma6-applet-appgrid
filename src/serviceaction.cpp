/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "serviceaction.h"

namespace ServiceAction
{
std::optional<KServiceAction> find(const KService::Ptr &service, const QString &actionName)
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
