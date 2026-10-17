/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appidsmodel.h"
#include "launchstatestore.h"

#include <QPointer>

/**
 * The hidden apps, for the lists that show them (the settings page and the
 * h: view): one row per hidden app, optionally narrowed to the ones whose
 * name or id contains filter. Follows the launch state store live, also when
 * another launcher hides or unhides one. An uninstalled app's name is its id.
 *
 * Each list creates its own (a QML type), given the controller's store, so
 * one list's filter doesn't narrow the other.
 */
class HiddenAppsModel : public AppIdsModel
{
    Q_OBJECT
    Q_PROPERTY(LaunchStateStore *launchState READ launchState WRITE setLaunchState NOTIFY launchStateChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    // Hidden apps exist at all, filter aside.
    Q_PROPERTY(bool empty READ isEmpty NOTIFY countChanged)

public:
    explicit HiddenAppsModel(QObject *parent = nullptr);

    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;

    [[nodiscard]] LaunchStateStore *launchState() const
    {
        return m_state.data();
    }
    void setLaunchState(LaunchStateStore *state);
    [[nodiscard]] QString filter() const
    {
        return m_filter;
    }
    void setFilter(const QString &text);
    [[nodiscard]] bool isEmpty() const;

    Q_INVOKABLE void unhide(const QString &storageId);
    Q_INVOKABLE void unhideAll();

Q_SIGNALS:
    void launchStateChanged();
    void filterChanged();

protected:
    void appsChanged() override;

private:
    void rebuild();

    QPointer<LaunchStateStore> m_state;
    QString m_filter;
};
