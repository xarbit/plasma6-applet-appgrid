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
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::enterFolder(const QString &relPath)
{
    if (relPath.isEmpty() || relPath == m_path) {
        return;
    }
    if (!MenuTree::findNode(m_root, relPath)) {
        return;
    }
    m_path = relPath;
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::goBack()
{
    if (m_path.isEmpty()) {
        return;
    }
    m_path = MenuTree::parentPath(m_path);
    rebuildRows();
    Q_EMIT pathChanged();
}

void MenuTreeModel::resetToRoot()
{
    if (m_path.isEmpty()) {
        return;
    }
    m_path.clear();
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
        Row row;
        row.type = Folder;
        row.folderId = folder.relPath;
        row.name = folder.name;
        row.members = MenuTree::previewMembers(folder, kPreviewMembers);
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
