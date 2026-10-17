/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>

#include <functional>

/**
 * @brief The id under which AppGrid stores a favourite in KActivities (#64).
 *
 * Pure decision (no KService/KActivities), so it unit-tests headlessly; the
 * model supplies the live menu-id resolver.
 */
namespace FavoriteId
{
/**
 * Normalise @p id to its stored form:
 *  - a jump-list action id ("…?action=…") is kept VERBATIM, so the action
 *    survives the round-trip — the whole reason AppGrid owns its favourites
 *    model rather than going through Kicker, which drops it here;
 *  - a plain app id is canonicalised to "applications:<menuId>" via
 *    @p menuIdResolver (called with the bare storage id; an empty return
 *    leaves @p id untouched, e.g. preferred:// or an unknown service).
 */
[[nodiscard]] QString normalized(const QString &id, const std::function<QString(const QString &)> &menuIdResolver);

/**
 * True when @p id is a document/file favourite — a local path or a URL whose
 * scheme is neither "applications" nor "preferred". Documents resolve and
 * launch differently from apps (mimetype icon, opened with the default app).
 */
[[nodiscard]] bool isDocument(const QString &id);

/**
 * The entries of @p stored that are the same favourite as @p id: those that
 * @p normalize maps to the same stored form. Older AppGrid versions stored an
 * app both bare ("foo.desktop") and prefixed ("applications:foo.desktop"), so
 * one favourite can have several stored variants; finding, adding and
 * removing a favourite must treat them as one. A jump-list action stays part
 * of the identity (normalized() keeps it verbatim).
 */
[[nodiscard]] QStringList variantsOf(const QStringList &stored, const QString &id, const std::function<QString(const QString &)> &normalize);
}
