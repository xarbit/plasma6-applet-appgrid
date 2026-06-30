/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

/**
 * Pure, Qt-free-of-QObject logic for the favourites folder layer (issue #18).
 *
 * Folders are an AppGrid-only grouping over the flat KAStats favourites list: a
 * top-level @c layout of ordered tokens ("app:<storageId>" or "folder:<id>")
 * plus a set of @c Folder definitions. KAStats stays the source of truth for
 * which apps are favourites; this layer only arranges them. Everything here is a
 * value transform — no model, no I/O — so it unit-tests directly (mirrors
 * frecencyscoring).
 */
namespace FavoritesFolderLogic
{

struct Folder {
    QString id;
    QString name;
    QStringList members; // ordered bare storageIds
    bool global = false; // shown in every activity, not just the current one

    bool operator==(const Folder &o) const
    {
        return id == o.id && name == o.name && members == o.members && global == o.global;
    }
};

struct Layout {
    QList<Folder> folders;
    QStringList tokens; // top-level order of "app:<sid>" / "folder:<id>"

    bool operator==(const Layout &o) const
    {
        return folders == o.folders && tokens == o.tokens;
    }
};

// Token helpers.
[[nodiscard]] QString appToken(const QString &storageId);
[[nodiscard]] QString folderToken(const QString &folderId);
[[nodiscard]] bool isAppToken(const QString &token);
[[nodiscard]] bool isFolderToken(const QString &token);
[[nodiscard]] QString tokenPayload(const QString &token); // sid or folder id

/**
 * Reconcile @p in against the live flat favourite list @p flatFavorites
 * (KAStats order). Pure; returns a normalised layout where:
 *  - folder members are KEPT regardless of favourite status, so a member added on
 *    another instance survives a reconcile against this instance's stale flat list
 *    (#18). Dead members (uninstalled app, deleted file) are hidden at render by
 *    FavoritesGroupedModel::shownMembers, not dropped here,
 *  - folders are kept at any size (empty or single included); only an explicit
 *    ungroup removes one,
 *  - loose favourites not in @p flatFavorites are dropped (cleans externally
 *    removed favourites),
 *  - every favourite appears in exactly one place (folder membership wins),
 *  - favourites absent from the layout are appended in @p flatFavorites order.
 */
[[nodiscard]] Layout reconcile(const QStringList &flatFavorites, const Layout &in);

// Mutations — each returns a new layout to be reconcile()d by the caller. A bad
// argument (unknown folder, identical sids) returns @p in unchanged.
[[nodiscard]] Layout createFolder(const Layout &in, const QString &sidA, const QString &sidB, const QString &name);
// Group two or more members (deduplicated) into a new folder anchored at the
// first member's slot. Fewer than two distinct members returns @p in unchanged.
[[nodiscard]] Layout createFolderWith(const Layout &in, const QStringList &members, const QString &name);
[[nodiscard]] Layout addToFolder(const Layout &in, const QString &folderId, const QString &sid);
[[nodiscard]] Layout removeFromFolder(const Layout &in, const QString &folderId, const QString &sid);
[[nodiscard]] Layout renameFolder(const Layout &in, const QString &folderId, const QString &name);
// Mark a folder shown in every activity (global) or only the current one.
[[nodiscard]] Layout setFolderGlobal(const Layout &in, const QString &folderId, bool global);
// Dissolve a folder: remove it and drop its members back in its place as loose
// top-level apps (they stay favourites).
[[nodiscard]] Layout dissolveFolder(const Layout &in, const QString &folderId);
[[nodiscard]] Layout moveTopLevel(const Layout &in, int fromRow, int toRow);
[[nodiscard]] Layout reorderInFolder(const Layout &in, const QString &folderId, int fromIndex, int toIndex);

/** Next free "f<n>" id given the existing folders. */
[[nodiscard]] QString nextFolderId(const QList<Folder> &folders);

// Boundary conversions for the QVariant world (QML + LaunchStateStore).
[[nodiscard]] QVariantList foldersToVariant(const QList<Folder> &folders);
[[nodiscard]] QList<Folder> foldersFromVariant(const QVariantList &list);
// On-disk form: one compact-JSON object per StringList entry.
[[nodiscard]] QStringList foldersToJsonList(const QVariantList &folders);
[[nodiscard]] QVariantList foldersFromJsonList(const QStringList &list);

}
