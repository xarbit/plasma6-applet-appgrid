/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "abstractgroupedmodel.h"
#include "menutree.h"

#include <QString>

/**
 * @brief Read-only, multi-level category folders over the app-menu tree (#201).
 *
 * A navigable cursor onto a MenuTree::Node tree. AbstractGroupedModel only
 * speaks one level (App leaves + Folder groups with flat members), so instead of
 * nesting Folder rows this model rebases: the visible rows are always the
 * children of the current path, and entering a folder moves the cursor down
 * rather than opening another model. That keeps the existing folder UI and its
 * row contract unchanged while supporting arbitrary menu depth.
 *
 * Authoring lives in kmenuedit, so the model is never editable — create / rename
 * / reorder / add-to-folder stay off. The tree is handed in whole (the
 * production KServiceGroup walk builds it and refeeds it on KSycoca changes);
 * this class owns only navigation, so it has no KSycoca dependency and is
 * unit-tested against a synthetic tree.
 */
class MenuTreeModel : public AbstractGroupedModel
{
    Q_OBJECT
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY pathChanged)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY pathChanged)
    Q_PROPERTY(QString currentFolderName READ currentFolderName NOTIFY pathChanged)
    // When true, folders with no app anywhere in their subtree are dropped from
    // the listing ("hide empty categories"). Live: toggling rebuilds the rows.
    Q_PROPERTY(bool hideEmpty READ hideEmpty WRITE setHideEmpty NOTIFY hideEmptyChanged)

public:
    explicit MenuTreeModel(QObject *parent = nullptr);

    /** Replace the whole menu tree and reset navigation to the root. */
    void setTree(MenuTree::Node root);

    // isEditable() is left at the base default (false): authoring lives in
    // kmenuedit, so the UI's create / rename / reorder / add-to-folder stay off.

    [[nodiscard]] bool hideEmpty() const
    {
        return m_hideEmpty;
    }
    void setHideEmpty(bool enabled);

    /** Set the navigation floor and show it: the listing roots at @p relPath
     *  (empty = all categories) and Back never climbs above it. The category bar
     *  uses this so a selected category tab shows that category's contents flat
     *  with its subfolders, and going back lands at the category, not all
     *  categories (#201). Tolerates a missing trailing slash. */
    Q_INVOKABLE void setRootPath(const QString &relPath);

    /** Descend into the folder at @p relPath. Tolerates a missing trailing slash
     *  (the category bar's menu path is stored without it). No-op if absent. */
    Q_INVOKABLE void enterFolder(const QString &relPath);
    /** Step up one level; a no-op at the root floor. */
    Q_INVOKABLE void goBack();
    /** Jump back to the root floor. */
    Q_INVOKABLE void resetToRoot();

    [[nodiscard]] bool canGoBack() const
    {
        return m_path != m_rootPath;
    }
    [[nodiscard]] QString currentPath() const
    {
        return m_path;
    }
    [[nodiscard]] QString currentFolderName() const;

Q_SIGNALS:
    void pathChanged();
    void hideEmptyChanged();

private:
    // Rebuild the visible rows from the node at m_path: child folders become
    // Folder rows (with a gathered 2x2 preview), direct apps become App rows.
    void rebuildRows();

    MenuTree::Node m_root;
    QString m_path; // current node relPath; empty = root
    QString m_rootPath; // navigation floor; Back never climbs above it
    bool m_hideEmpty = false;

    // 2x2 folder preview.
    static constexpr int kPreviewMembers = 4;
};
