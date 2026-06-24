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

public:
    explicit MenuTreeModel(QObject *parent = nullptr);

    /** Replace the whole menu tree and reset navigation to the root. */
    void setTree(MenuTree::Node root);

    // isEditable() is left at the base default (false): authoring lives in
    // kmenuedit, so the UI's create / rename / reorder / add-to-folder stay off.

    /** Descend into the folder at @p relPath (a no-op if it isn't in the tree). */
    Q_INVOKABLE void enterFolder(const QString &relPath);
    /** Step up one level; a no-op at the root. */
    Q_INVOKABLE void goBack();
    /** Jump back to the top-level listing. */
    Q_INVOKABLE void resetToRoot();

    [[nodiscard]] bool canGoBack() const
    {
        return !m_path.isEmpty();
    }
    [[nodiscard]] QString currentPath() const
    {
        return m_path;
    }
    [[nodiscard]] QString currentFolderName() const;

Q_SIGNALS:
    void pathChanged();

private:
    // Rebuild the visible rows from the node at m_path: child folders become
    // Folder rows (with a gathered 2x2 preview), direct apps become App rows.
    void rebuildRows();

    MenuTree::Node m_root;
    QString m_path; // current node relPath; empty = root

    // 2x2 folder preview.
    static constexpr int kPreviewMembers = 4;
};
