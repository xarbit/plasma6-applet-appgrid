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
    // A distinct config name per test so they never share on-disk state.
    auto cfg = KSharedConfig::openConfig(QStringLiteral("appgrid-test-%1rc").arg(m_seq));
    cfg->group(QStringLiteral("General")).deleteGroup();
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

QTEST_MAIN(TestLaunchStateStore)
#include "test_launchstatestore.moc"
