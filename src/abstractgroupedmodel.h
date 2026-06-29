/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QStringList>

/**
 * @brief Source-agnostic base for a grid of app leaves mixed with folder groups.
 *
 * Defines the row contract the QML grid + folder UI bind to and nothing else —
 * no data source, no persistence, no lifecycle. A row is either an @c App leaf
 * (carrying the favourite id the existing launch path already understands) or a
 * @c Folder group (carrying a name + member storageIds for the 2x2 preview).
 *
 * Concrete subclasses own where the rows come from: FavoritesGroupedModel
 * (editable, KAStats-backed, issue #18) and, later, a read-only category model
 * over the app menu tree. The folder UI never learns which — it only reads this
 * contract and @c editable.
 */
class AbstractGroupedModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool editable READ isEditable CONSTANT)

public:
    enum EntryType {
        App = 0,
        Folder = 1,
    };
    Q_ENUM(EntryType)

    enum Roles {
        EntryTypeRole = Qt::UserRole + 1,
        FavoriteIdRole,
        FolderIdRole,
        FolderMembersRole,
        MemberCountRole,
        // Qt::DisplayRole carries the app/folder name.
    };

    explicit AbstractGroupedModel(QObject *parent = nullptr);

    [[nodiscard]] int rowCount(const QModelIndex &parent = {}) const override;
    [[nodiscard]] QVariant data(const QModelIndex &index, int role) const override;
    [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

    /** Member storageIds of @p folderId, empty if it is not a folder here. */
    [[nodiscard]] Q_INVOKABLE QStringList folderMembers(const QString &folderId) const;
    /** Display name of @p folderId, empty if it is not a folder here. */
    [[nodiscard]] Q_INVOKABLE QString folderName(const QString &folderId) const;
    /** The folder id that currently contains @p sid, empty if none. */
    [[nodiscard]] Q_INVOKABLE QString folderOfMember(const QString &sid) const;

    // Row accessors for QML keyboard activation, which has no delegate context to
    // read named roles from.
    [[nodiscard]] Q_INVOKABLE int entryTypeAt(int row) const;
    [[nodiscard]] Q_INVOKABLE QString folderIdAt(int row) const;
    [[nodiscard]] Q_INVOKABLE QString favoriteIdAt(int row) const;
    /** Row of the Folder @p folderId among the visible rows, or -1. */
    [[nodiscard]] Q_INVOKABLE int indexOfFolder(const QString &folderId) const;
    /** Row of the App with @p favoriteId among the visible rows, or -1. */
    [[nodiscard]] Q_INVOKABLE int indexOfApp(const QString &favoriteId) const;

    /** Whether the UI may create/rename/reorder folders against this source. */
    [[nodiscard]] virtual bool isEditable() const
    {
        return false;
    }

protected:
    struct Row {
        EntryType type = App;
        QString favoriteId; // App: "applications:<sid>"
        QString folderId; // Folder
        QString name; // Folder name (App rows resolve their own name in QML)
        QStringList members; // Folder members
    };

    /** Replace the visible rows. Subclasses call this after rebuilding. */
    void setRows(const QList<Row> &rows);

    /** Move one visible row, emitting beginMoveRows/endMoveRows so the view can
     *  animate it (rather than the full reset setRows does). Subclasses keep
     *  their own ordering in sync alongside this. */
    void moveRowAt(int from, int to);

private:
    QList<Row> m_rows;
};
