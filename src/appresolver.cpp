/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appresolver.h"

#include "appactionid.h"
#include "favoriteid.h"

#include <QFileInfo>
#include <QMimeDatabase>

namespace AppResolver
{
namespace
{
Target resolveDocument(const QString &id)
{
    // A bare local path is a file; anything else is taken as a URL.
    const QUrl url = id.startsWith(QLatin1Char('/')) ? QUrl::fromLocalFile(id) : QUrl(id);
    Target target;
    // A deleted local file is a dead favourite; a remote URL is assumed reachable.
    if (url.isLocalFile() && !QFileInfo::exists(url.toLocalFile())) {
        return target;
    }
    const QMimeDatabase mimeDb;
    const QMimeType mime = url.isLocalFile() ? mimeDb.mimeTypeForFile(url.toLocalFile()) : mimeDb.mimeTypeForUrl(url);
    target.documentUrl = url;
    target.name = url.fileName().isEmpty() ? url.toString() : url.fileName();
    target.icon = mime.iconName();
    return target;
}
}

Target resolve(const QString &id)
{
    if (id.isEmpty()) {
        return {};
    }
    if (FavoriteId::isDocument(id)) {
        return resolveDocument(id);
    }

    const AppActionId::Parsed parsed = AppActionId::parse(id);
    Target target;
    // Tries the menu id, then the desktop path, the file and the desktop name.
    target.service = KService::serviceByStorageId(parsed.storageId);
    if (!target.service) {
        return {};
    }
    if (!parsed.actionName.isEmpty()) {
        target.action = AppActionId::resolveAction(target.service, parsed.actionName);
    }
    if (target.action) {
        target.name = target.action->text();
        target.icon = target.action->icon().isEmpty() ? target.service->icon() : target.action->icon();
    } else {
        target.name = target.service->name();
        target.icon = target.service->icon();
    }
    return target;
}

QList<KServiceAction> actions(const KService::Ptr &service)
{
    QList<KServiceAction> labelled;
    if (!service) {
        return labelled;
    }
    const auto all = service->actions();
    for (const KServiceAction &action : all) {
        if (!action.text().isEmpty()) {
            labelled.append(action);
        }
    }
    return labelled;
}

QVariantMap actionData(const QString &id)
{
    const Target target = resolve(id);
    if (!target.action) {
        return {};
    }
    return {
        {QStringLiteral("name"), target.name},
        {QStringLiteral("iconName"), target.icon},
        {QStringLiteral("desktopFile"), target.service->entryPath()},
        {QStringLiteral("storageId"), id},
        {QStringLiteral("genericName"), target.service->genericName()},
        {QStringLiteral("comment"), target.service->comment()},
        {QStringLiteral("installSource"), QString()},
    };
}
}
