/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appfieldscache.h"
#include "launchstatestore.h"

#include <QAbstractListModel>
#include <QPointer>
#include <QStringList>

/**
 * The hidden apps, for the lists that show them (the settings page and the
 * h: view): one row per hidden app with its name and icon, optionally
 * narrowed to the ones whose name or id contains filter. Follows the launch
 * state store live, also when another launcher hides or unhides one.
 *
 * Each list creates its own (a QML type), given the controller's store, so
 * one list's filter doesn't narrow the other.
 */
class HiddenAppsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(LaunchStateStore *launchState READ launchState WRITE setLaunchState NOTIFY launchStateChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    // Hidden apps exist at all, filter aside.
    Q_PROPERTY(bool empty READ isEmpty NOTIFY countChanged)

public:
    enum Roles {
        StorageIdRole = Qt::UserRole + 1,
        NameRole,
        IconNameRole,
        GenericNameRole,
    };

    explicit HiddenAppsModel(QObject *parent = nullptr);

    [[nodiscard]] LaunchStateStore *launchState() const
    {
        return m_state;
    }
    void setLaunchState(LaunchStateStore *state);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] QString filter() const
    {
        return m_filter;
    }
    void setFilter(const QString &filter);
    [[nodiscard]] bool isEmpty() const;

    Q_INVOKABLE void unhide(const QString &storageId);
    Q_INVOKABLE void unhideAll();

Q_SIGNALS:
    void launchStateChanged();
    void filterChanged();
    void countChanged();

private:
    void rebuild();

    QPointer<LaunchStateStore> m_state;
    QString m_filter;
    QStringList m_rows;
    AppFieldsCache m_fields;
};
