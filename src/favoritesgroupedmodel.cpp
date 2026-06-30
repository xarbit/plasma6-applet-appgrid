/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "favoritesgroupedmodel.h"

#include "pluginhelpers.h"

using namespace FavoritesFolderLogic;

FavoritesGroupedModel::FavoritesGroupedModel(QObject *parent)
    : AbstractGroupedModel(parent)
{
}

QVariantList FavoritesGroupedModel::favoriteFolders() const
{
    return foldersToVariant(m_state.folders);
}

void FavoritesGroupedModel::setFavoriteFolders(const QVariantList &folders)
{
    const QList<FavoritesFolderLogic::Folder> incoming = foldersFromVariant(folders);
    if (incoming == m_state.folders) {
        return;
    }
    apply(reconcile(m_flatFavorites, {incoming, m_state.tokens}));
}

QStringList FavoritesGroupedModel::favoriteLayout() const
{
    return m_state.tokens;
}

void FavoritesGroupedModel::setFavoriteLayout(const QStringList &layout)
{
    if (layout == m_state.tokens) {
        return;
    }
    apply(reconcile(m_flatFavorites, {m_state.folders, layout}));
}

void FavoritesGroupedModel::setFlatFavorites(const QStringList &flatFavorites)
{
    if (flatFavorites == m_flatFavorites) {
        return;
    }
    m_flatFavorites = flatFavorites;
    apply(reconcile(m_flatFavorites, m_state));
    // apply() rebuilds only when the layout moved, but the shown members also
    // depend on the flat list (a removed favourite must drop out of a folder's
    // preview even when the token order is unchanged), so refresh regardless.
    rebuildRows();
}

void FavoritesGroupedModel::setKnownApps(const QStringList &storageIds)
{
    const QSet<QString> next(storageIds.cbegin(), storageIds.cend());
    if (next == m_knownApps) {
        return;
    }
    m_knownApps = next;
    // Only the shown rows depend on this (which members resolve); the layout is
    // untouched, so just rebuild — no reconcile / persist.
    rebuildRows();
}

void FavoritesGroupedModel::addLooseFavorite(const QString &sid, int index)
{
    if (sid.isEmpty() || m_flatFavorites.contains(sid)) {
        return;
    }
    m_flatFavorites.append(sid);
    auto next = reconcile(m_flatFavorites, m_state);
    // reconcile appends the new favourite as a loose token at the end; drop it at
    // the cursor slot so it appears under the pointer, not at the bottom (which
    // would then animate up to the cursor).
    if (index >= 0) {
        const int from = next.tokens.indexOf(FavoritesFolderLogic::appToken(sid));
        if (from >= 0) {
            next.tokens.move(from, qBound(0, index, next.tokens.size() - 1));
        }
    }
    // No persist: the real KAStats favourite (added in parallel by the UI) is the
    // source of truth; a follow-up reorder persists the final layout position.
    apply(next, false);
}

void FavoritesGroupedModel::removeLooseFavorite(const QString &sid)
{
    if (!m_flatFavorites.removeOne(sid)) {
        return;
    }
    apply(reconcile(m_flatFavorites, m_state), false);
}

QString FavoritesGroupedModel::createFolder(const QString &sidA, const QString &sidB, const QString &name)
{
    return _applyCreate(FavoritesFolderLogic::createFolder(m_state, sidA, sidB, name));
}

QString FavoritesGroupedModel::createFolderFromMembers(const QStringList &sids, const QString &name)
{
    _adoptFavorites(sids);
    return _applyCreate(FavoritesFolderLogic::createFolderWith(m_state, sids, name));
}

QString FavoritesGroupedModel::createEmptyFolder(const QString &name)
{
    return _applyCreate(FavoritesFolderLogic::createFolderWith(m_state, {}, name));
}

QString FavoritesGroupedModel::_applyCreate(const Layout &next)
{
    // A new folder is appended last; pick up its id, apply, then announce it so
    // the UI can prompt for a name.
    if (next.folders.size() <= m_state.folders.size()) {
        return {};
    }
    const QString id = next.folders.constLast().id;
    apply(reconcile(m_flatFavorites, next), true);
    Q_EMIT folderCreated(id);
    return id;
}

void FavoritesGroupedModel::addToFolder(const QString &folderId, const QString &sid)
{
    _adoptFavorites({sid});
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::addToFolder(m_state, folderId, sid)), true);
}

void FavoritesGroupedModel::_adoptFavorites(const QStringList &sids)
{
    // The UI favourites a non-favourite app (in KAStats) just before grouping it.
    // KAStats only reports the new favourite a tick later, so optimistically take
    // these into the flat list now so the app reads as a favourite immediately;
    // the next real push carries the same id, and the contains() guard makes
    // re-adopting a no-op. (Folder membership itself no longer depends on this —
    // reconcile keeps members regardless of favourite status, see #18.)
    for (const QString &sid : sids) {
        if (!sid.isEmpty() && !m_flatFavorites.contains(sid)) {
            m_flatFavorites.append(sid);
        }
    }
}

void FavoritesGroupedModel::removeFromFolder(const QString &folderId, const QString &sid)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::removeFromFolder(m_state, folderId, sid)), true);
}

void FavoritesGroupedModel::renameFolder(const QString &folderId, const QString &name)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::renameFolder(m_state, folderId, name)), true);
}

void FavoritesGroupedModel::setFolderGlobal(const QString &folderId, bool global)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::setFolderGlobal(m_state, folderId, global)), true);
}

int FavoritesGroupedModel::folderIndex(const QString &folderId) const
{
    for (int i = 0; i < m_state.folders.size(); ++i) {
        if (m_state.folders.at(i).id == folderId) {
            return i;
        }
    }
    return -1;
}

bool FavoritesGroupedModel::isFolderGlobal(const QString &folderId) const
{
    const int idx = folderIndex(folderId);
    return idx >= 0 && m_state.folders.at(idx).global;
}

void FavoritesGroupedModel::ungroupFolder(const QString &folderId)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::dissolveFolder(m_state, folderId)), true);
}

void FavoritesGroupedModel::moveTopLevel(int fromRow, int toRow)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::moveTopLevel(m_state, fromRow, toRow)), true);
}

void FavoritesGroupedModel::enterFolder(const QString &folderId)
{
    if (folderId.isEmpty() || folderId == m_openFolder || folderIndex(folderId) < 0) {
        return;
    }
    m_openFolder = folderId;
    rebuildRows();
    Q_EMIT pathChanged();
}

void FavoritesGroupedModel::goBack()
{
    if (m_openFolder.isEmpty()) {
        return;
    }
    m_openFolder.clear();
    rebuildRows();
    Q_EMIT pathChanged();
}

void FavoritesGroupedModel::resetToRoot()
{
    goBack();
}

QString FavoritesGroupedModel::currentFolderName() const
{
    const int idx = folderIndex(m_openFolder);
    return idx >= 0 ? m_state.folders.at(idx).name : QString();
}

void FavoritesGroupedModel::moveRow(int fromRow, int toRow)
{
    // Inside a folder, reorder its members (a pure move, like the top level).
    if (!m_openFolder.isEmpty()) {
        const int idx = folderIndex(m_openFolder);
        if (idx < 0) {
            return;
        }
        QStringList &members = m_state.folders[idx].members;
        if (fromRow < 0 || toRow < 0 || fromRow >= members.size() || toRow >= members.size() || fromRow == toRow) {
            return;
        }
        members.move(fromRow, toRow);
        moveRowAt(fromRow, toRow);
        Q_EMIT foldersChanged();
        Q_EMIT foldersPersistRequested();
        return;
    }

    if (fromRow < 0 || toRow < 0 || fromRow >= m_state.tokens.size() || toRow >= m_state.tokens.size() || fromRow == toRow) {
        return;
    }
    // The layout stays valid under a pure reorder, so move the token + the row
    // in lockstep and emit a row-move instead of reconciling (which would reset).
    m_state.tokens.move(fromRow, toRow);
    moveRowAt(fromRow, toRow);
    Q_EMIT layoutChanged();
    Q_EMIT layoutPersistRequested();
}

void FavoritesGroupedModel::reorderInFolder(const QString &folderId, int fromIndex, int toIndex)
{
    apply(reconcile(m_flatFavorites, FavoritesFolderLogic::reorderInFolder(m_state, folderId, fromIndex, toIndex)), true);
}

void FavoritesGroupedModel::apply(const Layout &next, bool persist)
{
    const bool foldersMoved = next.folders != m_state.folders;
    const bool tokensMoved = next.tokens != m_state.tokens;
    if (!foldersMoved && !tokensMoved) {
        return;
    }
    m_state = next;
    rebuildRows();
    if (foldersMoved) {
        Q_EMIT foldersChanged();
        if (persist) {
            Q_EMIT foldersPersistRequested();
        }
    }
    if (tokensMoved) {
        Q_EMIT layoutChanged();
        if (persist) {
            Q_EMIT layoutPersistRequested();
        }
    }
}

QStringList FavoritesGroupedModel::shownMembers(const QStringList &members) const
{
    if (m_knownApps.isEmpty()) {
        return members;
    }
    QStringList shown;
    shown.reserve(members.size());
    for (const QString &sid : members) {
        if (m_knownApps.contains(sid) || m_flatFavorites.contains(sid)) {
            shown.append(sid);
        }
    }
    return shown;
}

void FavoritesGroupedModel::rebuildRows()
{
    // Drilled into a folder: show its renderable members as app rows. If the
    // folder is gone, or every member is now dead (uninstalled/unfavourited), fall
    // back to the top level and announce it so the UI drops its back affordance.
    if (!m_openFolder.isEmpty()) {
        const int idx = folderIndex(m_openFolder);
        const QStringList members = idx >= 0 ? shownMembers(m_state.folders.at(idx).members) : QStringList();
        if (!members.isEmpty()) {
            QList<Row> rows;
            rows.reserve(members.size());
            for (const QString &sid : members) {
                Row row;
                row.type = AbstractGroupedModel::App;
                row.favoriteId = PluginHelpers::toFavoriteId(sid);
                rows.append(row);
            }
            setRows(rows);
            return;
        }
        m_openFolder.clear();
        Q_EMIT pathChanged();
    }

    QList<Row> rows;
    rows.reserve(m_state.tokens.size());
    for (const QString &token : m_state.tokens) {
        if (isFolderToken(token)) {
            const int idx = folderIndex(tokenPayload(token));
            if (idx >= 0) {
                const FavoritesFolderLogic::Folder &f = m_state.folders.at(idx);
                rows.append({AbstractGroupedModel::Folder, {}, f.id, f.name, shownMembers(f.members)});
            }
        } else if (isAppToken(token)) {
            Row row;
            row.type = AbstractGroupedModel::App;
            row.favoriteId = PluginHelpers::toFavoriteId(tokenPayload(token));
            rows.append(row);
        }
    }
    setRows(rows);
}
