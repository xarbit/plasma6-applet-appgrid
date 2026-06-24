/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "abstractgroupedmodel.h"
#include "menutree.h"
#include "menutreemodel.h"

#include <QSignalSpy>
#include <QTest>

using namespace MenuTree;

namespace
{
RawFolder folder(const QString &relPath, const QString &name)
{
    return RawFolder{relPath, name, QStringLiteral("folder")};
}
RawApp app(const QString &folderRelPath, const QString &storageId)
{
    return RawApp{folderRelPath, AppLeaf{storageId, storageId, QStringLiteral("app")}};
}

// A small two-deep menu:
//   (root)        -> rootapp.desktop
//   Education/     -> edu.desktop
//   Education/Science/ -> sci1.desktop, sci2.desktop
Node sampleTree()
{
    const QList<RawFolder> folders = {
        folder(QStringLiteral("Education/"), QStringLiteral("Education")),
        // Deliberately list the child before the parent to prove depth-ordering.
        folder(QStringLiteral("Education/Science/"), QStringLiteral("Science")),
    };
    const QList<RawApp> apps = {
        app(QString(), QStringLiteral("rootapp.desktop")),
        app(QStringLiteral("Education/"), QStringLiteral("edu.desktop")),
        app(QStringLiteral("Education/Science/"), QStringLiteral("sci1.desktop")),
        app(QStringLiteral("Education/Science/"), QStringLiteral("sci2.desktop")),
    };
    return build(folders, apps);
}
}

class TestMenuTree : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parentPath_strips_one_level();
    void build_nests_regardless_of_input_order();
    void build_keeps_orphans_and_unknown_apps();
    void previewMembers_gathers_subtree_capped();
    void model_lists_current_level();
    void model_navigates_in_and_out();
    void model_ignores_unknown_folder();
    void model_is_not_editable();
};

void TestMenuTree::parentPath_strips_one_level()
{
    QCOMPARE(MenuTree::parentPath(QStringLiteral("Education/Science/")), QStringLiteral("Education/"));
    QCOMPARE(MenuTree::parentPath(QStringLiteral("Education/")), QString());
    // Tolerates a missing trailing slash.
    QCOMPARE(MenuTree::parentPath(QStringLiteral("Education/Science")), QStringLiteral("Education/"));
    QCOMPARE(MenuTree::parentPath(QString()), QString());
}

void TestMenuTree::build_nests_regardless_of_input_order()
{
    const Node root = sampleTree();

    const Node *edu = findNode(root, QStringLiteral("Education/"));
    QVERIFY(edu);
    QCOMPARE(edu->name, QStringLiteral("Education"));
    QCOMPARE(edu->folders.size(), size_t(1));
    QCOMPARE(edu->apps.size(), size_t(1));
    QCOMPARE(edu->apps.front().storageId, QStringLiteral("edu.desktop"));

    const Node *sci = findNode(root, QStringLiteral("Education/Science/"));
    QVERIFY(sci);
    QCOMPARE(sci->name, QStringLiteral("Science"));
    QCOMPARE(sci->apps.size(), size_t(2));

    // Root carries its own app and exactly the one top-level folder.
    QCOMPARE(root.folders.size(), size_t(1));
    QCOMPARE(root.apps.size(), size_t(1));
}

void TestMenuTree::build_keeps_orphans_and_unknown_apps()
{
    // A folder whose parent isn't present and an app pointing at a missing
    // folder both fall back to the root rather than vanishing.
    const QList<RawFolder> folders = {folder(QStringLiteral("Ghost/Child/"), QStringLiteral("Child"))};
    const QList<RawApp> apps = {app(QStringLiteral("Nowhere/"), QStringLiteral("lost.desktop"))};
    const Node root = build(folders, apps);

    QCOMPARE(root.folders.size(), size_t(1));
    QCOMPARE(root.folders.front().relPath, QStringLiteral("Ghost/Child/"));
    QCOMPARE(root.apps.size(), size_t(1));
    QCOMPARE(root.apps.front().storageId, QStringLiteral("lost.desktop"));
}

void TestMenuTree::previewMembers_gathers_subtree_capped()
{
    const Node root = sampleTree();
    const Node *edu = findNode(root, QStringLiteral("Education/"));
    QVERIFY(edu);

    // Own app first, then the descendant's apps, capped at the limit.
    const QStringList three = previewMembers(*edu, 3);
    QCOMPARE(three, QStringList({QStringLiteral("edu.desktop"), QStringLiteral("sci1.desktop"), QStringLiteral("sci2.desktop")}));

    const QStringList one = previewMembers(*edu, 1);
    QCOMPARE(one, QStringList({QStringLiteral("edu.desktop")}));

    QVERIFY(previewMembers(*edu, 0).isEmpty());
}

void TestMenuTree::model_lists_current_level()
{
    MenuTreeModel model;
    model.setTree(sampleTree());

    // Root: one folder row (Education) + one app row (rootapp), folder first.
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.data(model.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::Folder));
    QCOMPARE(model.data(model.index(0), AbstractGroupedModel::FolderIdRole).toString(), QStringLiteral("Education/"));
    QCOMPARE(model.data(model.index(0), Qt::DisplayRole).toString(), QStringLiteral("Education"));
    QCOMPARE(model.data(model.index(1), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::App));
    QCOMPARE(model.data(model.index(1), AbstractGroupedModel::FavoriteIdRole).toString(), QStringLiteral("applications:rootapp.desktop"));

    QVERIFY(!model.canGoBack());
    QCOMPARE(model.currentPath(), QString());
    QCOMPARE(model.currentFolderName(), QString());
}

void TestMenuTree::model_navigates_in_and_out()
{
    MenuTreeModel model;
    model.setTree(sampleTree());
    QSignalSpy pathSpy(&model, &MenuTreeModel::pathChanged);

    model.enterFolder(QStringLiteral("Education/"));
    QCOMPARE(pathSpy.count(), 1);
    QCOMPARE(model.currentPath(), QStringLiteral("Education/"));
    QCOMPARE(model.currentFolderName(), QStringLiteral("Education"));
    QVERIFY(model.canGoBack());
    // Education level: Science folder + edu app.
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.data(model.index(0), AbstractGroupedModel::FolderIdRole).toString(), QStringLiteral("Education/Science/"));

    model.enterFolder(QStringLiteral("Education/Science/"));
    QCOMPARE(model.currentPath(), QStringLiteral("Education/Science/"));
    // Two leaf apps, no sub-folders.
    QCOMPARE(model.rowCount(), 2);
    QCOMPARE(model.data(model.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::App));

    model.goBack();
    QCOMPARE(model.currentPath(), QStringLiteral("Education/"));
    model.goBack();
    QCOMPARE(model.currentPath(), QString());
    QVERIFY(!model.canGoBack());
    // goBack at the root is a no-op (no extra signal).
    const int before = pathSpy.count();
    model.goBack();
    QCOMPARE(pathSpy.count(), before);
}

void TestMenuTree::model_ignores_unknown_folder()
{
    MenuTreeModel model;
    model.setTree(sampleTree());
    QSignalSpy pathSpy(&model, &MenuTreeModel::pathChanged);

    model.enterFolder(QStringLiteral("Does/Not/Exist/"));
    QCOMPARE(pathSpy.count(), 0);
    QCOMPARE(model.currentPath(), QString());
    QCOMPARE(model.rowCount(), 2);
}

void TestMenuTree::model_is_not_editable()
{
    MenuTreeModel model;
    QVERIFY(!model.isEditable());
}

QTEST_MAIN(TestMenuTree)
#include "test_menutree.moc"
