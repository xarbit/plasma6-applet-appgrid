/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>
#include <KServiceAction>

#include <QString>

#include <optional>

/**
 * @brief Parse and resolve KRunner jump-list action favourite ids (#64).
 *
 * The services runner exposes a desktop action of an app as
 * "applications:<storageId>?action=<actionName>". Favouriting/launching that
 * needs the parent service plus the named KServiceAction (Plasma 6.7's
 * serviceActionFromUrl, reimplemented here so it works on every Plasma 6).
 */
namespace AppActionId
{
struct Parsed {
    QString storageId; ///< Storage id without the "applications:" scheme or the query.
    QString actionName; ///< Empty when the id is a plain app, not a jump-list action.
};

/** Split @p id into its storage id and action name. @p id may carry the
 *  "applications:" scheme or not. Pure (no KService), so it is unit-testable. */
[[nodiscard]] Parsed parse(const QString &id);

/** The bare id of @p actionName of @p storageId ("<storageId>?action=<name>"),
 *  or @p storageId alone for an empty @p actionName. The inverse of parse(). */
[[nodiscard]] QString compose(const QString &storageId, const QString &actionName);

/** True when @p id carries an "?action=" jump-list action. */
[[nodiscard]] bool hasAction(const QString &id);

/** The KServiceAction of @p service whose name() equals @p actionName, or
 *  nullopt if none matches. */
[[nodiscard]] std::optional<KServiceAction> resolveAction(const KService::Ptr &service, const QString &actionName);
}
