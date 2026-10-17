/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantList>

/**
 * @brief The one place the launcher starts what the user picked.
 *
 * Takes any id the views hold (see AppResolver: an app, a jump-list action or
 * a document) and starts it through AppLauncher. Every app launch is handled
 * the same way, wherever it came from (grid, search, favourites, folders,
 * context menu): it is reported to KActivities, so other launchers and
 * KRunner count it, and announced with appLaunched() for the launcher's own
 * recents and launch counts.
 */
class LaunchService : public QObject
{
    Q_OBJECT

public:
    explicit LaunchService(QObject *parent = nullptr);

    /** Start @p id. Returns false when it resolves to nothing launchable. */
    Q_INVOKABLE bool launch(const QString &id);
    /** Start the jump-list action @p actionName (KServiceAction::name()) of
     *  @p storageId. By name, not index: appActions() skips unlabelled ones. */
    Q_INVOKABLE bool launchAction(const QString &storageId, const QString &actionName);

    /** The labelled jump-list actions of @p storageId as {text, icon, name}. */
    [[nodiscard]] Q_INVOKABLE QVariantList appActions(const QString &storageId) const;

    /** The key an app launch is recorded under: the bare storage id, with
     *  "?action=<name>" for a jump-list action. Empty for a document. */
    [[nodiscard]] static QString launchKey(const QString &id);

Q_SIGNALS:
    /** An app or one of its actions was started; @p key is its launchKey(). */
    void appLaunched(const QString &key);
};
