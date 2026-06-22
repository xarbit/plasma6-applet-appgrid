/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for LaunchStateStore: the shared per-user launch state (hidden /
    recent / known apps + launch counts) persisted to appgridrc, the single
    source of truth both plasmoid variants and the daemon read.
*/

#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

#include <KSharedConfig>

#include "launchstatestore.h"

class TestLaunchStateStore : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void init();
    void setters_emitAndDedup();
    void launchCounts_roundtripThroughFile();
    void persists_acrossInstances();
    void migrateFrom_seedsOnlyAbsentKeys();
    void favoriteFolders_roundtripThroughFile();
    void perActivityFolders_scopeAndFallback();
    void favoriteLayout_roundtripThroughFile();

private:
    KSharedConfig::Ptr freshConfig();
    int m_seq = 0;
};

void TestLaunchStateStore::initTestCase()
{
    // Keep every read/write inside a throwaway XDG tree.
    QStandardPaths::setTestModeEnabled(true);
}

void TestLaunchStateStore::init()
{
    ++m_seq;
}

KSharedConfig::Ptr TestLaunchStateStore::freshConfig()
{
    // Wipe every group (not just [General]) so per-activity [Folders] state from
    // an earlier run or test never leaks in.
    auto cfg = KSharedConfig::openConfig(QStringLiteral("appgrid-test-%1rc").arg(m_seq));
    const QStringList groups = cfg->groupList();
    for (const QString &group : groups) {
        cfg->deleteGroup(group);
    }
    cfg->sync();
    return cfg;
}

void TestLaunchStateStore::setters_emitAndDedup()
{
    LaunchStateStore store(freshConfig());
    QSignalSpy spy(&store, &LaunchStateStore::hiddenAppsChanged);

    store.setHiddenApps({QStringLiteral("a.desktop")});
    QCOMPARE(spy.count(), 1);
    QCOMPARE(store.hiddenApps(), QStringList{QStringLiteral("a.desktop")});

    // Same value → no signal, no spurious save.
    store.setHiddenApps({QStringLiteral("a.desktop")});
    QCOMPARE(spy.count(), 1);
}

void TestLaunchStateStore::launchCounts_roundtripThroughFile()
{
    auto cfg = freshConfig();
    {
        LaunchStateStore store(cfg);
        store.setLaunchCounts({{QStringLiteral("a.desktop"), 3}, {QStringLiteral("b.desktop"), 1}});
        QTest::qWait(700); // let the debounced save fire
    }
    // The on-disk form is the "storageId=count" StringList the daemon used.
    const QStringList raw = cfg->group(QStringLiteral("General")).readEntry("launchCounts", QStringList());
    QVERIFY(raw.contains(QStringLiteral("a.desktop=3")));
    QVERIFY(raw.contains(QStringLiteral("b.desktop=1")));

    LaunchStateStore reopened(cfg);
    QCOMPARE(reopened.launchCounts().value(QStringLiteral("a.desktop")).toInt(), 3);
    QCOMPARE(reopened.launchCounts().value(QStringLiteral("b.desktop")).toInt(), 1);
}

void TestLaunchStateStore::persists_acrossInstances()
{
    auto cfg = freshConfig();
    {
        LaunchStateStore store(cfg);
        store.setHiddenApps({QStringLiteral("x.desktop")});
        store.setRecentApps({QStringLiteral("y.desktop")});
        store.setKnownApps({QStringLiteral("z.desktop")});
        QTest::qWait(700);
    }
    LaunchStateStore reopened(cfg);
    QCOMPARE(reopened.hiddenApps(), QStringList{QStringLiteral("x.desktop")});
    QCOMPARE(reopened.recentApps(), QStringList{QStringLiteral("y.desktop")});
    QCOMPARE(reopened.knownApps(), QStringList{QStringLiteral("z.desktop")});
}

void TestLaunchStateStore::migrateFrom_seedsOnlyAbsentKeys()
{
    auto cfg = freshConfig();
    LaunchStateStore store(cfg);
    store.setHiddenApps({QStringLiteral("already.desktop")});
    QTest::qWait(700); // the hidden list is now on disk

    // Migrate a different set: hidden is present, so it must NOT be clobbered;
    // recents/known/counts are absent, so they seed.
    const bool migrated =
        store.migrateFrom({QStringLiteral("old.desktop")}, {QStringLiteral("r.desktop")}, {QStringLiteral("k.desktop")}, {QStringLiteral("c.desktop=5")});
    QVERIFY(migrated);
    QCOMPARE(store.hiddenApps(), QStringList{QStringLiteral("already.desktop")});
    QCOMPARE(store.recentApps(), QStringList{QStringLiteral("r.desktop")});
    QCOMPARE(store.knownApps(), QStringList{QStringLiteral("k.desktop")});
    QCOMPARE(store.launchCounts().value(QStringLiteral("c.desktop")).toInt(), 5);

    // A second migrate finds every key present → no-op.
    QVERIFY(!store.migrateFrom({QStringLiteral("p.desktop")}, {}, {}, {}));
}

void TestLaunchStateStore::favoriteFolders_roundtripThroughFile()
{
    auto cfg = freshConfig();
    const QVariantList folders = {QVariantMap{
        {QStringLiteral("id"), QStringLiteral("f1")},
        {QStringLiteral("name"), QStringLiteral("Games")},
        {QStringLiteral("members"), QStringList({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")})},
    }};
    {
        LaunchStateStore store(cfg);
        store.setFavoriteFolders(folders);
        QTest::qWait(700);
    }
    // On disk: one compact-JSON object per StringList entry. No activity set, so
    // the shared default — the legacy [General] group.
    const QStringList raw = cfg->group(QStringLiteral("General")).readEntry("favoriteFolders", QStringList());
    QCOMPARE(raw.size(), 1);
    QVERIFY(raw.first().contains(QStringLiteral("Games")));

    LaunchStateStore reopened(cfg);
    QCOMPARE(reopened.favoriteFolders().size(), 1);
    QCOMPARE(reopened.favoriteFolders().first().toMap().value(QStringLiteral("id")).toString(), QStringLiteral("f1"));
    QCOMPARE(reopened.favoriteFolders().first().toMap().value(QStringLiteral("members")).toStringList().size(), 2);
}

void TestLaunchStateStore::perActivityFolders_scopeAndFallback()
{
    auto cfg = freshConfig();
    const auto folder = [](const QString &id, const QString &name) {
        return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("members"), QStringList{QStringLiteral("a.desktop")}}};
    };
    const auto nameOf = [](const LaunchStateStore &s) {
        return s.favoriteFolders().isEmpty() ? QString() : s.favoriteFolders().first().toMap().value(QStringLiteral("name")).toString();
    };

    // Seed a shared (no-activity) layout.
    {
        LaunchStateStore store(cfg);
        store.setFavoriteFolders({folder(QStringLiteral("g"), QStringLiteral("Shared"))});
        QTest::qWait(700);
    }
    // An activity with no layout of its own falls back to the shared one, then
    // editing copies-on-write into that activity's own group.
    {
        LaunchStateStore store(cfg);
        store.setActivity(QStringLiteral("activity-A"));
        QCOMPARE(nameOf(store), QStringLiteral("Shared"));
        store.setFavoriteFolders({folder(QStringLiteral("a"), QStringLiteral("WorkOnly"))});
        QTest::qWait(700);
    }
    // Activity A now has its own; the shared layout and other activities don't.
    {
        LaunchStateStore store(cfg);
        store.setActivity(QStringLiteral("activity-A"));
        QCOMPARE(nameOf(store), QStringLiteral("WorkOnly"));
    }
    {
        LaunchStateStore store(cfg); // no activity → shared
        QCOMPARE(nameOf(store), QStringLiteral("Shared"));
    }
    {
        LaunchStateStore store(cfg);
        store.setActivity(QStringLiteral("activity-B")); // never edited → shared
        QCOMPARE(nameOf(store), QStringLiteral("Shared"));
    }
}

void TestLaunchStateStore::favoriteLayout_roundtripThroughFile()
{
    auto cfg = freshConfig();
    const QStringList layout = {QStringLiteral("folder:f1"), QStringLiteral("app:c.desktop")};
    {
        LaunchStateStore store(cfg);
        store.setFavoriteLayout(layout);
        QTest::qWait(700);
    }
    LaunchStateStore reopened(cfg);
    QCOMPARE(reopened.favoriteLayout(), layout);
}

QTEST_MAIN(TestLaunchStateStore)
#include "test_launchstatestore.moc"
