/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appfieldscache.h"

#include <QAbstractListModel>
#include <QStringList>

/**
 * A list of app ids as rows with the app's fields, under the app model's role
 * names, resolved through AppFieldsCache and refreshed when the installed
 * apps change. Subclasses decide which ids (setIds()).
 */
class AppIdsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        StorageIdRole = Qt::UserRole + 1,
        NameRole,
        IconNameRole,
        GenericNameRole,
        CommentRole,
        DesktopFileRole,
        InstallSourceRole,
    };

    explicit AppIdsModel(QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

Q_SIGNALS:
    void countChanged();

protected:
    /** Show @p ids, in order. */
    void setIds(const QStringList &ids);
    [[nodiscard]] const AppFieldsCache &fields() const
    {
        return m_fields;
    }
    /** The installed apps changed; the fields are resolved again. */
    virtual void appsChanged();

private:
    QStringList m_ids;
    AppFieldsCache m_fields;
};
