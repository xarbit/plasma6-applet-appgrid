/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "abstractgroupedmodel.h"
#include "favoritesfolderlogic.h"

#include <QVariantList>

/**
 * @brief Editable grouped model for the favourites tab (issue #18).
 *
 * Owns the folder definitions and top-level layout (persisted to appgridrc via
 * LaunchStateStore). KAStats stays the source of truth for membership: QML pushes
 * the flat, ordered favourite list in via setFlatFavorites(), which reconciles
 * the layout (cleaning removed favourites, auto-ungrouping, appending new ones).
 * Folder mutations never touch KAStats — a grouped app is still a favourite.
 *
 * Holds no Kicker/AppFilterModel dependency, so it unit-tests headlessly; the
 * folder math lives in the pure FavoritesFolderLogic namespace.
 */
class FavoritesGroupedModel : public AbstractGroupedModel
{
    Q_OBJECT
    Q_PROPERTY(QVariantList favoriteFolders READ favoriteFolders WRITE setFavoriteFolders NOTIFY foldersChanged)
    Q_PROPERTY(QStringList favoriteLayout READ favoriteLayout WRITE setFavoriteLayout NOTIFY layoutChanged)
    // Drill-in-place navigation (issue #18): the visible rows are the top level
    // (folders + loose apps) or, inside a folder, that folder's members.
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY pathChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY pathChanged)
    Q_PROPERTY(QString currentFolderName READ currentFolderName NOTIFY pathChanged)

public:
    explicit FavoritesGroupedModel(QObject *parent = nullptr);

    [[nodiscard]] bool isEditable() const override
    {
        return true;
    }

    // --- Navigation (single level: top <-> one open folder) ---
    /** Show @p folderId's members; a no-op if it isn't a folder here. */
    Q_INVOKABLE void enterFolder(const QString &folderId);
    /** Back to the top level; a no-op already there. */
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void resetToRoot();
    [[nodiscard]] bool canGoBack() const
    {
        return !m_openFolder.isEmpty();
    }
    [[nodiscard]] QString currentPath() const
    {
        return m_openFolder;
    }
    [[nodiscard]] QString currentFolderName() const;

    [[nodiscard]] QVariantList favoriteFolders() const;
    void setFavoriteFolders(const QVariantList &folders);
    [[nodiscard]] QStringList favoriteLayout() const;
    void setFavoriteLayout(const QStringList &layout);

    /** The live, ordered favourite storageIds from KAStats. Reconciles. */
    Q_INVOKABLE void setFlatFavorites(const QStringList &flatFavorites);

    /** Optimistically add @p sid as a loose favourite *now*, so a drag-into-
     *  favourites reflows it instantly instead of waiting for the async KAStats
     *  round-trip. @p index is the visible slot to drop it at (the cursor), so it
     *  appears under the pointer rather than at the bottom; -1 appends. The UI
     *  favourites it in KAStats in parallel; the next real push carries the same id
     *  (the contains() guard makes it idempotent). #18 */
    Q_INVOKABLE void addLooseFavorite(const QString &sid, int index = -1);
    /** Roll back an optimistic addLooseFavorite (drag left without dropping). */
    Q_INVOKABLE void removeLooseFavorite(const QString &sid);

    // Folder mutations (config only — never touch KAStats membership).
    Q_INVOKABLE QString createFolder(const QString &sidA, const QString &sidB, const QString &name = {});
    Q_INVOKABLE QString createFolderFromMembers(const QStringList &sids, const QString &name = {});
    // An empty, named folder (created from blank grid space) to drag apps into.
    Q_INVOKABLE QString createEmptyFolder(const QString &name = {});
    Q_INVOKABLE void addToFolder(const QString &folderId, const QString &sid);
    Q_INVOKABLE void removeFromFolder(const QString &folderId, const QString &sid);
    Q_INVOKABLE void renameFolder(const QString &folderId, const QString &name);
    // Show a folder in every activity (global) or only the current one.
    Q_INVOKABLE void setFolderGlobal(const QString &folderId, bool global);
    [[nodiscard]] Q_INVOKABLE bool isFolderGlobal(const QString &folderId) const;
    // Dissolve a folder: its members return to the top level as loose favourites.
    Q_INVOKABLE void ungroupFolder(const QString &folderId);
    Q_INVOKABLE void moveTopLevel(int fromRow, int toRow);
    // Live single-row reorder for drag: moves the top-level token and emits a
    // row-move (no reconcile/reset) so the grid animates the displacement.
    Q_INVOKABLE void moveRow(int fromRow, int toRow);
    Q_INVOKABLE void reorderInFolder(const QString &folderId, int fromIndex, int toIndex);

Q_SIGNALS:
    void foldersChanged();
    void layoutChanged();
    // Navigation level changed (entered/left a folder, or the open folder
    // dissolved while inside it).
    void pathChanged();
    // Persist signals: emitted only for LOCAL user actions, never when applying an
    // incoming store/KAStats change. The store mirror writes on these so a process
    // that merely reads an external update never echoes it back — that write-back
    // is what let one instance clobber another's just-added folder member (#18).
    void foldersPersistRequested();
    void layoutPersistRequested();
    // A new folder was just created (drag-fold, menu, or empty) — the UI prompts
    // for its name.
    void folderCreated(const QString &folderId);

private:
    // Reconcile against the flat favourites, rebuild the visible rows, and emit
    // folders/layout changes when they actually moved. @p persist marks a local
    // user action so the change is written back to the store (see the signals).
    void apply(const FavoritesFolderLogic::Layout &next, bool persist = false);
    // Apply a create transform, returning + announcing the new folder id.
    QString _applyCreate(const FavoritesFolderLogic::Layout &next);
    // Optimistically take @p sids into the flat favourite list (the UI is
    // favouriting them in KAStats in the same step) so grouping survives reconcile.
    void _adoptFavorites(const QStringList &sids);
    void rebuildRows();
    // Index of the folder with @p folderId in m_state, or -1.
    [[nodiscard]] int folderIndex(const QString &folderId) const;

    FavoritesFolderLogic::Layout m_state;
    QStringList m_flatFavorites;
    // The folder currently drilled into; empty = top level.
    QString m_openFolder;
};
