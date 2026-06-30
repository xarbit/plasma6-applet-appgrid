/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "menutreemodel.h"

#include "pluginhelpers.h"

MenuTreeModel::MenuTreeModel(QObject *parent)
    : AbstractGroupedModel(parent)
{
}

void MenuTreeModel::setTree(MenuTree::Node root)
{
    m_root = std::move(root);
    m_path.clear();
    m_rootPath.clear();
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::setRootPath(const QString &relPath)
{
    // Normalise the floor (trailing slash; empty = all categories). An unknown
    // path falls back to the all-categories root.
    QString floor;
    if (!relPath.isEmpty()) {
        floor = relPath.endsWith(QLatin1Char('/')) ? relPath : relPath + QLatin1Char('/');
        if (!MenuTree::findNode(m_root, floor)) {
            floor.clear();
        }
    }
    if (floor == m_rootPath && floor == m_path) {
        return;
    }
    m_rootPath = floor;
    m_path = floor;
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::setHideEmpty(bool enabled)
{
    if (m_hideEmpty == enabled) {
        return;
    }
    m_hideEmpty = enabled;
    rebuildRows();
    Q_EMIT hideEmptyChanged();
}

void MenuTreeModel::enterFolder(const QString &relPath)
{
    if (relPath.isEmpty()) {
        return;
    }
    // KServiceGroup relPaths carry a trailing slash; the category bar's stored
    // menu path does not. Normalise so either form enters the same folder.
    const QString target = relPath.endsWith(QLatin1Char('/')) ? relPath : relPath + QLatin1Char('/');
    if (target == m_path || !MenuTree::findNode(m_root, target)) {
        return;
    }
    m_path = target;
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::goBack()
{
    if (m_path == m_rootPath) {
        return;
    }
    QString parent = MenuTree::parentPath(m_path);
    // Never climb above the floor.
    if (parent.length() < m_rootPath.length()) {
        parent = m_rootPath;
    }
    m_path = parent;
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::resetToRoot()
{
    if (m_path == m_rootPath) {
        return;
    }
    m_path = m_rootPath;
    rebuildRows();
    Q_EMIT pathChanged();
}

QString MenuTreeModel::currentFolderName() const
{
    const MenuTree::Node *node = MenuTree::findNode(m_root, m_path);
    return node ? node->name : QString();
}

void MenuTreeModel::rebuildRows()
{
    const MenuTree::Node *node = MenuTree::findNode(m_root, m_path);
    if (!node) {
        setRows({});
        return;
    }

    QList<Row> rows;
    rows.reserve(static_cast<int>(node->folders.size() + node->apps.size()));

    for (const MenuTree::Node &folder : node->folders) {
        // previewMembers gathers the whole subtree, so an empty list means the
        // folder has no app anywhere under it — drop it when hiding empties.
        const QStringList members = MenuTree::previewMembers(folder, kPreviewMembers);
        if (m_hideEmpty && members.isEmpty()) {
            continue;
        }
        Row row;
        row.type = Folder;
        row.folderId = folder.relPath;
        row.name = folder.name;
        row.members = members;
        rows.append(row);
    }
    for (const MenuTree::AppLeaf &app : node->apps) {
        Row row;
        row.type = App;
        row.favoriteId = PluginHelpers::toFavoriteId(app.storageId);
        row.name = app.name;
        rows.append(row);
    }

    setRows(rows);
}
