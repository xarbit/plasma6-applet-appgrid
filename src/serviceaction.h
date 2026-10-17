/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>

#include <QString>

#include <optional>

namespace ServiceAction
{
/** The KServiceAction of @p service whose name() equals @p actionName, or
 *  nullopt if none matches. App actions are launched by name: the context menu
 *  lists only actions with text, so its row index doesn't match actions(). */
[[nodiscard]] std::optional<KServiceAction> find(const KService::Ptr &service, const QString &actionName);
}
