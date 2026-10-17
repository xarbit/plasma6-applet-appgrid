/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>
#include <KServiceAction>

#include <QList>
#include <QString>
#include <QUrl>

#include <optional>

/**
 * @brief What an id the launcher shows stands for, and how to show and start it.
 *
 * One place resolves every kind of id: a storage id, bare or with the
 * "applications:" scheme; a jump-list action ("…?action=<name>", #64); or a
 * document favourite (a local path or a URL).
 */
namespace AppResolver
{
struct Target {
    KService::Ptr service;
    // Set for a jump-list action of service.
    std::optional<KServiceAction> action;
    // Set for a document instead of service.
    QUrl documentUrl;
    QString name;
    QString icon;

    /** An installed app or action, or a document that exists. */
    [[nodiscard]] bool isValid() const
    {
        return service || documentUrl.isValid();
    }
};

/** Resolve @p id. An uninstalled app or a deleted local file is invalid. */
[[nodiscard]] Target resolve(const QString &id);

/** The jump-list actions of @p service that have a label. */
[[nodiscard]] QList<KServiceAction> actions(const KService::Ptr &service);
}
