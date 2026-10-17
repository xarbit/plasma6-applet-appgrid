/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "favoriteid.h"

#include "appactionid.h"
#include "appurl.h"

#include <QUrl>

QString FavoriteId::normalized(const QString &id, const std::function<QString(const QString &)> &menuIdResolver)
{
    if (id.isEmpty()) {
        return {};
    }
    if (AppActionId::hasAction(id)) {
        return id;
    }
    const QString menuId = menuIdResolver(AppActionId::parse(id).storageId);
    if (!menuId.isEmpty()) {
        return AppUrl::Scheme + menuId;
    }
    return id;
}

bool FavoriteId::isDocument(const QString &id)
{
    if (id.isEmpty()) {
        return false;
    }
    if (id.startsWith(QLatin1Char('/'))) {
        return true;
    }
    const QString scheme = QUrl(id).scheme();
    return !scheme.isEmpty() && scheme != QLatin1String("applications") && scheme != QLatin1String("preferred");
}

QStringList FavoriteId::variantsOf(const QStringList &stored, const QString &id, const std::function<QString(const QString &)> &normalize)
{
    const QString target = normalize(id);
    if (target.isEmpty()) {
        return {};
    }
    QStringList variants;
    for (const QString &entry : stored) {
        if (!variants.contains(entry) && normalize(entry) == target) {
            variants.append(entry);
        }
    }
    return variants;
}

QStringList FavoriteId::plainIds(const QStringList &stored)
{
    QStringList ids;
    ids.reserve(stored.size());
    for (const QString &entry : stored) {
        if (!entry.isEmpty()) {
            ids.append(AppUrl::stripScheme(entry));
        }
    }
    return ids;
}
