/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for FavoritesGroupedModel — the editable grouped model over the
    flat favourites list (issue #18). Pins the role contract exposed to the grid
    delegate and that mutations + flat-list pushes keep the model consistent.
*/

#include <QSignalSpy>
#include <QTest>

#include "favoritesgroupedmodel.h"

class TestFavoritesGroupedModel : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void isEditable();
    void flatFavouritesBecomeAppRows();
    void appRowExposesFavoriteId();
    void createFolderProducesFolderRow();
    void folderRowExposesMembers();
    void removeFromFolderEmitsAndUngroups();
    void createFolderFromMembersGroupsAll();
    void ungroupFolderFreesMembers();
    void moveRowReordersLayout();
    void addToFolderAdoptsNonFavourite();
    void folderMemberSurvivesStaleFavouritesPush();
    void layoutSurvivesReloadById();
    void enterFolderShowsMembersThenGoBack();
    void moveRowInFolderReordersMembers();
    void emptyingOpenFolderExitsToTop();
    void indexOfFolderAndApp();
    void addLooseFavoriteIsImmediateAndIdempotent();
    void uninstalledFolderMemberHiddenButKept();
};

void TestFavoritesGroupedModel::isEditable()
{
    FavoritesGroupedModel m;
    QVERIFY(m.isEditable());
}

void TestFavoritesGroupedModel::flatFavouritesBecomeAppRows()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    QCOMPARE(m.rowCount(), 2);
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::App));
}

void TestFavoritesGroupedModel::appRowExposesFavoriteId()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop")});
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::FavoriteIdRole).toString(), QStringLiteral("applications:a.desktop"));
}

void TestFavoritesGroupedModel::createFolderProducesFolderRow()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("Work"));
    QVERIFY(!id.isEmpty());
    // One folder row (a+b) plus the loose c → 2 rows.
    QCOMPARE(m.rowCount(), 2);
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::Folder));
    QCOMPARE(m.data(m.index(0), Qt::DisplayRole).toString(), QStringLiteral("Work"));
}

void TestFavoritesGroupedModel::folderRowExposesMembers()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::MemberCountRole).toInt(), 2);
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")}));
}

void TestFavoritesGroupedModel::removeFromFolderEmitsAndUngroups()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    m.addToFolder(id, QStringLiteral("c.desktop"));
    QSignalSpy spy(&m, &FavoritesGroupedModel::foldersChanged);
    m.removeFromFolder(id, QStringLiteral("c.desktop"));
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")}));
}

void TestFavoritesGroupedModel::createFolderFromMembersGroupsAll()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id =
        m.createFolderFromMembers({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}, QStringLiteral("All"));
    QCOMPARE(m.rowCount(), 1); // one folder, no loose apps
    QCOMPARE(m.folderMembers(id).size(), 3);
}

void TestFavoritesGroupedModel::ungroupFolderFreesMembers()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    QCOMPARE(m.rowCount(), 1);
    m.ungroupFolder(id);
    // Folder gone; both apps back as loose favourites.
    QCOMPARE(m.rowCount(), 2);
    QVERIFY(m.folderMembers(id).isEmpty());
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::App));
}

void TestFavoritesGroupedModel::moveRowReordersLayout()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    m.moveRow(0, 2); // a → end
    QCOMPARE(m.favoriteLayout(), QStringList({QStringLiteral("app:b.desktop"), QStringLiteral("app:c.desktop"), QStringLiteral("app:a.desktop")}));
    QCOMPARE(m.data(m.index(2), AbstractGroupedModel::FavoriteIdRole).toString(), QStringLiteral("applications:a.desktop"));
}

void TestFavoritesGroupedModel::addToFolderAdoptsNonFavourite()
{
    // Adding an app the model doesn't yet know as a favourite (the UI favourites
    // it in the same step) must keep it in the folder, not drop it on reconcile.
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    m.addToFolder(id, QStringLiteral("c.desktop")); // c not in the flat list yet
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}));
}

void TestFavoritesGroupedModel::folderMemberSurvivesStaleFavouritesPush()
{
    // The UI favourites c then groups it, but a flat-favourites push (this or
    // another instance, KAStats lagging) omits c. Folder membership doesn't track
    // favourite status, so c must stay in the folder rather than reappear as a
    // loose favourite (#18).
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    m.addToFolder(id, QStringLiteral("c.desktop"));

    // Stale push (c not in the flat list) — c must NOT be dropped or go loose.
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}));
    QCOMPARE(m.favoriteLayout(), QStringList{QStringLiteral("folder:") + id});

    // Only an explicit remove takes c out of the folder, not favourite churn.
    m.removeFromFolder(id, QStringLiteral("c.desktop"));
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")}));
}

void TestFavoritesGroupedModel::layoutSurvivesReloadById()
{
    // Folders + layout round-trip through the QVariant/StringList properties
    // (what LaunchStateStore persists), keeping the stable id.
    FavoritesGroupedModel src;
    src.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = src.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("Games"));

    FavoritesGroupedModel restored;
    restored.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    restored.setFavoriteFolders(src.favoriteFolders());
    restored.setFavoriteLayout(src.favoriteLayout());
    QCOMPARE(restored.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")}));
    QCOMPARE(restored.data(restored.index(0), Qt::DisplayRole).toString(), QStringLiteral("Games"));
}

void TestFavoritesGroupedModel::enterFolderShowsMembersThenGoBack()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("Work"));

    // Top level: the folder row + the loose app.
    QVERIFY(!m.canGoBack());
    QCOMPARE(m.rowCount(), 2);

    QSignalSpy pathSpy(&m, &FavoritesGroupedModel::pathChanged);
    m.enterFolder(id);
    QCOMPARE(pathSpy.count(), 1);
    QVERIFY(m.canGoBack());
    QCOMPARE(m.currentFolderName(), QStringLiteral("Work"));
    // Inside: the two members as app rows.
    QCOMPARE(m.rowCount(), 2);
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::EntryTypeRole).toInt(), int(AbstractGroupedModel::App));
    QCOMPARE(m.data(m.index(0), AbstractGroupedModel::FavoriteIdRole).toString(), QStringLiteral("applications:a.desktop"));

    m.goBack();
    QVERIFY(!m.canGoBack());
    QCOMPARE(m.rowCount(), 2); // folder + loose app again
}

void TestFavoritesGroupedModel::moveRowInFolderReordersMembers()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolderFromMembers({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});

    m.enterFolder(id);
    m.moveRow(0, 2); // a -> end
    m.goBack(); // folderMembers reads the top-level folder row
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("b.desktop"), QStringLiteral("c.desktop"), QStringLiteral("a.desktop")}));
}

void TestFavoritesGroupedModel::emptyingOpenFolderExitsToTop()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));

    m.enterFolder(id);
    QVERIFY(m.canGoBack());
    // Removing members until the folder dissolves should drop us back to the top.
    m.removeFromFolder(id, QStringLiteral("a.desktop"));
    m.removeFromFolder(id, QStringLiteral("b.desktop"));
    QVERIFY(!m.canGoBack());
    QCOMPARE(m.currentPath(), QString());
}

void TestFavoritesGroupedModel::indexOfFolderAndApp()
{
    // The shared lookups used by the drill views (re-select on back, reorder).
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("Work"));

    // Top level: folder row + the loose app.
    QCOMPARE(m.indexOfFolder(id), 0);
    QCOMPARE(m.indexOfApp(QStringLiteral("applications:c.desktop")), 1);
    QCOMPARE(m.indexOfFolder(QStringLiteral("nope")), -1);
    QCOMPARE(m.indexOfApp(QStringLiteral("applications:a.desktop")), -1); // grouped, not loose
}

void TestFavoritesGroupedModel::addLooseFavoriteIsImmediateAndIdempotent()
{
    FavoritesGroupedModel m;
    m.setFlatFavorites({QStringLiteral("a.desktop")});
    QCOMPARE(m.rowCount(), 1);

    // Optimistic add shows the row synchronously (no KAStats round-trip).
    m.addLooseFavorite(QStringLiteral("b.desktop"));
    QCOMPARE(m.rowCount(), 2);
    QCOMPARE(m.indexOfApp(QStringLiteral("applications:b.desktop")), 1);

    // An explicit index drops it at that slot (under the cursor), not the end.
    m.addLooseFavorite(QStringLiteral("c.desktop"), 0);
    QCOMPARE(m.indexOfApp(QStringLiteral("applications:c.desktop")), 0);
    m.removeLooseFavorite(QStringLiteral("c.desktop"));

    // The real KAStats push carrying the same id is a no-op (idempotent).
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    QCOMPARE(m.rowCount(), 2);

    // Rollback removes it again.
    m.removeLooseFavorite(QStringLiteral("b.desktop"));
    QCOMPARE(m.indexOfApp(QStringLiteral("applications:b.desktop")), -1);
}

void TestFavoritesGroupedModel::uninstalledFolderMemberHiddenButKept()
{
    // A folder of three installed, favourited apps.
    FavoritesGroupedModel m;
    m.setKnownApps({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    const QString id = m.createFolder(QStringLiteral("a.desktop"), QStringLiteral("b.desktop"));
    m.addToFolder(id, QStringLiteral("c.desktop"));
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}));

    // b is uninstalled: gone from the installed set and the favourites list.
    m.setKnownApps({QStringLiteral("a.desktop"), QStringLiteral("c.desktop")});
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("c.desktop")});
    // Hidden from the preview (the folder row's members) ...
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("c.desktop")}));
    // ... and from the drilled-in rows.
    m.enterFolder(id);
    QCOMPARE(m.rowCount(), 2);
    m.goBack();
    // ... but kept persisted (so a reinstall restores it).
    QCOMPARE(m.favoriteFolders().first().toMap().value(QStringLiteral("members")).toStringList(),
             QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}));

    // c is still installed but momentarily absent from this instance's flat list
    // (a cross-process favourite change): it stays visible via the installed set.
    m.setFlatFavorites({QStringLiteral("a.desktop")});
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("c.desktop")}));

    // Reinstalling b restores it — the layout kept it all along.
    m.setKnownApps({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    m.setFlatFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    QCOMPARE(m.folderMembers(id), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")}));
}

QTEST_GUILESS_MAIN(TestFavoritesGroupedModel)
#include "test_favoritesgroupedmodel.moc"
