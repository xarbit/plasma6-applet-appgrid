/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "menutree.h"

#include <algorithm>

namespace
{
// Depth of a canonical menu path = number of '/' separators. Root ("") is 0,
// "Education/" is 1, "Education/Science/" is 2. Used to link shallow folders
// before deep ones so a parent always exists when its child is inserted.
int pathDepth(const QString &relPath)
{
    return static_cast<int>(std::count(relPath.cbegin(), relPath.cend(), QLatin1Char('/')));
}

// Mutable lookup by exact relPath (empty = root). nullptr if absent.
MenuTree::Node *findNodeMut(MenuTree::Node &root, const QString &relPath)
{
    if (root.relPath == relPath) {
        return &root;
    }
    for (auto &child : root.folders) {
        if (MenuTree::Node *hit = findNodeMut(child, relPath)) {
            return hit;
        }
    }
    return nullptr;
}
}

namespace MenuTree
{

QString parentPath(const QString &relPath)
{
    QString trimmed = relPath;
    if (trimmed.endsWith(QLatin1Char('/'))) {
        trimmed.chop(1);
    }
    const int slash = trimmed.lastIndexOf(QLatin1Char('/'));
    return slash < 0 ? QString() : trimmed.left(slash + 1);
}

const Node *findNode(const Node &root, const QString &relPath)
{
    if (root.relPath == relPath) {
        return &root;
    }
    for (const auto &child : root.folders) {
        if (const Node *hit = findNode(child, relPath)) {
            return hit;
        }
    }
    return nullptr;
}

Node build(const QList<RawFolder> &folders, const QList<RawApp> &apps)
{
    Node root; // empty relPath, no name/icon

    // Link folders shallow-first so each one's parent is already in the tree.
    QList<RawFolder> ordered = folders;
    std::stable_sort(ordered.begin(), ordered.end(), [](const RawFolder &a, const RawFolder &b) {
        return pathDepth(a.relPath) < pathDepth(b.relPath);
    });

    for (const RawFolder &f : ordered) {
        Node *parent = findNodeMut(root, parentPath(f.relPath));
        if (!parent) {
            parent = &root; // orphan: parent group missing, hang it off the root
        }
        Node node;
        node.relPath = f.relPath;
        node.name = f.name;
        node.icon = f.icon;
        parent->folders.push_back(std::move(node));
    }

    for (const RawApp &a : apps) {
        Node *owner = findNodeMut(root, a.folderRelPath);
        if (!owner) {
            owner = &root; // unknown folder: keep the app rather than drop it
        }
        owner->apps.push_back(a.leaf);
    }

    return root;
}

QStringList previewMembers(const Node &node, int max)
{
    QStringList out;
    if (max <= 0) {
        return out;
    }
    // This node's own apps first, then descendants depth-first, so a folder's
    // preview leads with what sits directly in it.
    for (const AppLeaf &leaf : node.apps) {
        if (out.size() >= max) {
            return out;
        }
        out.append(leaf.storageId);
    }
    for (const Node &child : node.folders) {
        if (out.size() >= max) {
            return out;
        }
        out.append(previewMembers(child, max - out.size()));
    }
    return out;
}

} // namespace MenuTree
