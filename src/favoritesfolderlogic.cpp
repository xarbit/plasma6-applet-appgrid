/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "favoritesfolderlogic.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>

namespace FavoritesFolderLogic
{
namespace
{
const QLatin1String kAppPrefix("app:");
const QLatin1String kFolderPrefix("folder:");
// Folder ids are "f" + a monotonic number ("f1", "f2", …).
constexpr QLatin1Char kFolderIdPrefix('f');

// Index of the folder with @p id, or -1.
int folderIndex(const QList<Folder> &folders, const QString &id)
{
    for (int i = 0; i < folders.size(); ++i) {
        if (folders.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

// Members deduplicated, preserving first-seen order. Folder membership is the
// user's intent and is NOT filtered by favourite status: a member that isn't
// currently a favourite (e.g. KAStats lagging just after add, or an unfavourite
// on another instance) must stay, otherwise a cross-process reconcile round-trip
// drops a just-added member back out to loose favourites (#18).
QStringList dedupMembers(const QStringList &members)
{
    QStringList out;
    QSet<QString> seen;
    for (const QString &m : members) {
        if (!m.isEmpty() && !seen.contains(m)) {
            out.append(m);
            seen.insert(m);
        }
    }
    return out;
}
}

QString appToken(const QString &storageId)
{
    return kAppPrefix + storageId;
}

QString folderToken(const QString &folderId)
{
    return kFolderPrefix + folderId;
}

bool isAppToken(const QString &token)
{
    return token.startsWith(kAppPrefix);
}

bool isFolderToken(const QString &token)
{
    return token.startsWith(kFolderPrefix);
}

QString tokenPayload(const QString &token)
{
    if (isAppToken(token)) {
        return token.mid(kAppPrefix.size());
    }
    if (isFolderToken(token)) {
        return token.mid(kFolderPrefix.size());
    }
    return {};
}

Layout reconcile(const QStringList &flatFavorites, const Layout &in)
{
    // An empty favourite list is ambiguous: the user has no favourites, or
    // KAStats simply hasn't loaded yet (true at startup). Dissolving every
    // persisted folder in the latter case loses the user's groups, so treat
    // "no favourites" as "unknown" and keep the layout intact.
    if (flatFavorites.isEmpty()) {
        return in;
    }

    const QSet<QString> favSet(flatFavorites.cbegin(), flatFavorites.cend());

    // Folders are persistent, user-managed containers: keep every folder at any
    // size (empty or single included) so create-empty + add-to-folder work and
    // building a folder up doesn't dissolve it. Members are kept regardless of
    // favourite status (cross-process add safety, #18) — the grouped model hides
    // dead ones at render; explicit ungroup is the way to delete a folder.
    QList<Folder> folders;
    QSet<QString> inFolder;
    QSet<QString> folderIds;
    for (const Folder &f : in.folders) {
        const QStringList members = dedupMembers(f.members);
        folders.append({f.id, f.name, members, f.global});
        folderIds.insert(f.id);
        for (const QString &m : members) {
            inFolder.insert(m);
        }
    }

    Layout out;
    out.folders = folders;
    QSet<QString> placedApps;
    QSet<QString> placedFolders;

    // Keep existing tokens in order, dropping anything stale or now-foldered.
    for (const QString &tok : in.tokens) {
        if (isFolderToken(tok)) {
            const QString id = tokenPayload(tok);
            if (folderIds.contains(id) && !placedFolders.contains(id)) {
                out.tokens.append(tok);
                placedFolders.insert(id);
            }
        } else if (isAppToken(tok)) {
            const QString sid = tokenPayload(tok);
            if (favSet.contains(sid) && !inFolder.contains(sid) && !placedApps.contains(sid)) {
                out.tokens.append(tok);
                placedApps.insert(sid);
            }
        }
    }

    // Folders missing from the layout (e.g. just created) go in next, in order.
    for (const Folder &f : folders) {
        if (!placedFolders.contains(f.id)) {
            out.tokens.append(folderToken(f.id));
            placedFolders.insert(f.id);
        }
    }

    // Favourites not yet placed (newly added externally) append in KAStats order.
    for (const QString &sid : flatFavorites) {
        if (inFolder.contains(sid) || placedApps.contains(sid)) {
            continue;
        }
        out.tokens.append(appToken(sid));
        placedApps.insert(sid);
    }

    return out;
}

Layout createFolder(const Layout &in, const QString &sidA, const QString &sidB, const QString &name)
{
    return createFolderWith(in, {sidA, sidB}, name);
}

Layout createFolderWith(const Layout &in, const QStringList &members, const QString &name)
{
    const QStringList unique = dedupMembers(members);
    Layout out = in;
    Folder folder{nextFolderId(out.folders), name, unique};
    out.folders.append(folder);

    // No members (an empty folder created from blank space) → just append the
    // folder token at the end.
    if (unique.isEmpty()) {
        out.tokens.append(folderToken(folder.id));
        return out;
    }

    // Anchor the new folder at the first member's slot; drop the others' loose
    // tokens. reconcile() drops any stragglers (folder membership wins).
    const QString &anchor = unique.first();
    const QSet<QString> fold(unique.cbegin() + 1, unique.cend());
    bool anchored = false;
    QStringList tokens;
    for (const QString &tok : out.tokens) {
        if (isAppToken(tok) && tokenPayload(tok) == anchor) {
            tokens.append(folderToken(folder.id));
            anchored = true;
        } else if (isAppToken(tok) && fold.contains(tokenPayload(tok))) {
            continue;
        } else {
            tokens.append(tok);
        }
    }
    if (!anchored) {
        tokens.append(folderToken(folder.id));
    }
    out.tokens = tokens;
    return out;
}

Layout dissolveFolder(const Layout &in, const QString &folderId)
{
    QStringList freed;
    for (const Folder &f : in.folders) {
        if (f.id == folderId) {
            freed = f.members;
            break;
        }
    }

    Layout out;
    for (const Folder &f : in.folders) {
        if (f.id != folderId) {
            out.folders.append(f);
        }
    }
    // Replace the folder's token with its members as loose app tokens, in place.
    for (const QString &tok : in.tokens) {
        if (isFolderToken(tok) && tokenPayload(tok) == folderId) {
            for (const QString &m : freed) {
                out.tokens.append(appToken(m));
            }
        } else {
            out.tokens.append(tok);
        }
    }
    return out;
}

Layout addToFolder(const Layout &in, const QString &folderId, const QString &sid)
{
    const int target = folderIndex(in.folders, folderId);
    if (target < 0 || sid.isEmpty()) {
        return in;
    }
    // A member lives in exactly one folder — moving it elsewhere drops it from
    // its current one first.
    Layout out = in;
    for (Folder &f : out.folders) {
        f.members.removeAll(sid);
    }
    out.folders[target].members.append(sid);
    return out;
}

Layout removeFromFolder(const Layout &in, const QString &folderId, const QString &sid)
{
    const int target = folderIndex(in.folders, folderId);
    if (target < 0) {
        return in;
    }
    Layout out = in;
    out.folders[target].members.removeAll(sid);
    return out;
}

Layout renameFolder(const Layout &in, const QString &folderId, const QString &name)
{
    const int target = folderIndex(in.folders, folderId);
    if (target < 0) {
        return in;
    }
    Layout out = in;
    out.folders[target].name = name;
    return out;
}

Layout setFolderGlobal(const Layout &in, const QString &folderId, bool global)
{
    const int target = folderIndex(in.folders, folderId);
    if (target < 0) {
        return in;
    }
    Layout out = in;
    out.folders[target].global = global;
    return out;
}

Layout moveTopLevel(const Layout &in, int fromRow, int toRow)
{
    if (fromRow < 0 || fromRow >= in.tokens.size() || toRow < 0 || toRow >= in.tokens.size() || fromRow == toRow) {
        return in;
    }
    Layout out = in;
    out.tokens.move(fromRow, toRow);
    return out;
}

Layout reorderInFolder(const Layout &in, const QString &folderId, int fromIndex, int toIndex)
{
    const int target = folderIndex(in.folders, folderId);
    if (target < 0) {
        return in;
    }
    const QStringList &members = in.folders.at(target).members;
    if (fromIndex < 0 || fromIndex >= members.size() || toIndex < 0 || toIndex >= members.size()) {
        return in;
    }
    Layout out = in;
    out.folders[target].members.move(fromIndex, toIndex);
    return out;
}

QString nextFolderId(const QList<Folder> &folders)
{
    int max = 0;
    for (const Folder &f : folders) {
        if (f.id.startsWith(kFolderIdPrefix)) {
            bool ok = false;
            const int n = f.id.mid(1).toInt(&ok);
            if (ok && n > max) {
                max = n;
            }
        }
    }
    return kFolderIdPrefix + QString::number(max + 1);
}

QVariantList foldersToVariant(const QList<Folder> &folders)
{
    QVariantList list;
    list.reserve(folders.size());
    for (const Folder &f : folders) {
        QVariantMap map;
        map[QStringLiteral("id")] = f.id;
        map[QStringLiteral("name")] = f.name;
        map[QStringLiteral("members")] = f.members;
        // Only emit when set — old entries without the key read back as local.
        if (f.global) {
            map[QStringLiteral("global")] = true;
        }
        list.append(map);
    }
    return list;
}

QList<Folder> foldersFromVariant(const QVariantList &list)
{
    QList<Folder> folders;
    folders.reserve(list.size());
    for (const QVariant &v : list) {
        const QVariantMap map = v.toMap();
        const QString id = map.value(QStringLiteral("id")).toString();
        if (id.isEmpty()) {
            continue;
        }
        folders.append({id,
                        map.value(QStringLiteral("name")).toString(),
                        map.value(QStringLiteral("members")).toStringList(),
                        map.value(QStringLiteral("global")).toBool()});
    }
    return folders;
}

QStringList foldersToJsonList(const QVariantList &folders)
{
    QStringList list;
    list.reserve(folders.size());
    for (const QVariant &v : folders) {
        const QJsonObject obj = QJsonObject::fromVariantMap(v.toMap());
        list.append(QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)));
    }
    return list;
}

QVariantList foldersFromJsonList(const QStringList &list)
{
    QVariantList folders;
    folders.reserve(list.size());
    for (const QString &entry : list) {
        const QJsonDocument doc = QJsonDocument::fromJson(entry.toUtf8());
        if (doc.isObject()) {
            folders.append(doc.object().toVariantMap());
        }
    }
    return folders;
}

}
