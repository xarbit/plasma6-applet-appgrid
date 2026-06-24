/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QString>
#include <QStringList>

#include <vector>

/**
 * @brief Pure, read-only model of the XDG application-menu tree (issue #201).
 *
 * The kmenuedit menu is an arbitrary-depth tree of folders (.directory groups)
 * holding apps. AppGrid is a reader: kmenuedit authors the tree, the .directory
 * files own folder names/icons, KServiceGroup hands us the structure. This
 * namespace is the in-memory shape plus the pure assembly over it, so the build
 * and the preview/navigation maths are unit-tested without KSycoca — the
 * production KServiceGroup walk only has to emit the flat Raw* inputs.
 *
 * Single-level grouped models (AbstractGroupedModel) can't express folders
 * inside folders, so MenuTreeModel navigates this tree one level at a time
 * instead — see menutreemodel.h.
 */
namespace MenuTree
{

/** An app sitting directly in a folder. Pre-extracted from KService so QML reads
 *  cached strings, never a live service lookup while browsing. */
struct AppLeaf {
    QString storageId;
    QString name;
    QString icon;
};

/** One menu folder and everything directly under it. @c relPath is the canonical
 *  trailing-slash menu path ("Education/", "Education/Science/"); the root is the
 *  empty path with no name/icon. */
struct Node {
    QString relPath;
    QString name;
    QString icon;
    std::vector<Node> folders;
    std::vector<AppLeaf> apps;
};

/** A folder as the KServiceGroup walk sees it: its menu path plus the .directory
 *  caption + icon. */
struct RawFolder {
    QString relPath;
    QString name;
    QString icon;
};

/** An app placement: the menu path of the folder it belongs to (empty = root)
 *  plus the leaf itself. An app reachable from several groups yields several. */
struct RawApp {
    QString folderRelPath;
    AppLeaf leaf;
};

/** Assemble the node tree. Folders are linked under their parent path (shallow
 *  first, so the parent always exists); an orphan whose parent is missing falls
 *  back to the root. Apps drop into the node whose relPath matches, else root. */
[[nodiscard]] Node build(const QList<RawFolder> &folders, const QList<RawApp> &apps);

/** Up to @p max representative leaf storage ids from @p node's subtree (its own
 *  apps first, then descendants depth-first) for the 2x2 folder preview. */
[[nodiscard]] QStringList previewMembers(const Node &node, int max);

/** The node at exact @p relPath (empty returns @p root), or nullptr if absent. */
[[nodiscard]] const Node *findNode(const Node &root, const QString &relPath);

/** Parent of a menu path: "Education/Science/" -> "Education/"; one level -> "".
 *  Tolerates a missing trailing slash. */
[[nodiscard]] QString parentPath(const QString &relPath);

} // namespace MenuTree
