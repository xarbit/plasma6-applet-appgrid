/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for NewAppsTracker: the Kickoff-style new-app detection — a
    persisted installed-apps baseline plus per-app FirstSeen, with a recency
    window. KActivities usage is injected as null here (covered by the live
    UsedAppsProvider), so these exercise the baseline/diff/window logic.
*/

#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

#include <KConfigGroup>
#include <KSharedConfig>

#include "newappstracker.h"

class TestNewAppsTracker : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void firstRunSeedsBaselineNothingNew();
    void appAbsentFromBaselineIsNew();
    void uninstallPrunesFirstSeen();
    void expiredFirstSeenIsNotNew();
    void freshFirstSeenIsNew();
    void emptyRefreshKeepsBaseline();

private:
    KSharedConfig::Ptr freshConfig();
    int m_seq = 0;
};

void TestNewAppsTracker::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
}

KSharedConfig::Ptr TestNewAppsTracker::freshConfig()
{
    auto cfg = KSharedConfig::openConfig(QStringLiteral("appgrid-newapps-%1rc").arg(++m_seq));
    const QStringList groups = cfg->groupList();
    for (const QString &group : groups) {
        cfg->deleteGroup(group);
    }
    cfg->sync();
    return cfg;
}

void TestNewAppsTracker::firstRunSeedsBaselineNothingNew()
{
    NewAppsTracker tracker(nullptr, freshConfig());
    tracker.refresh({QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("c")});
    // Empty baseline → everything is treated as already-known; nothing flashes new.
    QVERIFY(tracker.newApps().isEmpty());
}

void TestNewAppsTracker::appAbsentFromBaselineIsNew()
{
    auto cfg = freshConfig();
    NewAppsTracker tracker(nullptr, cfg);
    tracker.refresh({QStringLiteral("a"), QStringLiteral("b")}); // seed baseline
    QSignalSpy spy(&tracker, &NewAppsTracker::newAppsChanged);
    tracker.refresh({QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("d")});
    QCOMPARE(tracker.newApps(), QSet<QString>{QStringLiteral("d")});
    QCOMPARE(spy.count(), 1);
    // Baseline grew on disk so a later run won't re-flag d.
    QVERIFY(cfg->group(QStringLiteral("NewApps")).readEntry("installedApps", QStringList()).contains(QStringLiteral("d")));
}

void TestNewAppsTracker::uninstallPrunesFirstSeen()
{
    auto cfg = freshConfig();
    NewAppsTracker tracker(nullptr, cfg);
    tracker.refresh({QStringLiteral("a")});
    tracker.refresh({QStringLiteral("a"), QStringLiteral("d")}); // d is new
    QCOMPARE(tracker.newApps(), QSet<QString>{QStringLiteral("d")});
    tracker.refresh({QStringLiteral("a")}); // d uninstalled → gone, not new
    QVERIFY(tracker.newApps().isEmpty());
    const QStringList firstSeen = cfg->group(QStringLiteral("NewApps")).readEntry("firstSeen", QStringList());
    QVERIFY(firstSeen.isEmpty());
}

void TestNewAppsTracker::expiredFirstSeenIsNotNew()
{
    auto cfg = freshConfig();
    // An app first seen well outside the 3-day window is no longer new.
    KConfigGroup g = cfg->group(QStringLiteral("NewApps"));
    g.writeEntry("installedApps", QStringList{QStringLiteral("a")});
    g.writeEntry("firstSeen", QStringList{QStringLiteral("a=") + QDate::currentDate().addDays(-5).toString(Qt::ISODate)});
    cfg->sync();

    NewAppsTracker tracker(nullptr, cfg);
    QVERIFY(tracker.newApps().isEmpty());
}

void TestNewAppsTracker::freshFirstSeenIsNew()
{
    auto cfg = freshConfig();
    KConfigGroup g = cfg->group(QStringLiteral("NewApps"));
    g.writeEntry("installedApps", QStringList{QStringLiteral("a")});
    g.writeEntry("firstSeen", QStringList{QStringLiteral("a=") + QDate::currentDate().toString(Qt::ISODate)});
    cfg->sync();

    NewAppsTracker tracker(nullptr, cfg);
    QCOMPARE(tracker.newApps(), QSet<QString>{QStringLiteral("a")});
}

void TestNewAppsTracker::emptyRefreshKeepsBaseline()
{
    auto cfg = freshConfig();
    NewAppsTracker tracker(nullptr, cfg);
    tracker.refresh({QStringLiteral("a"), QStringLiteral("b")}); // seed baseline
    // The model not being loaded yet (empty list) must not wipe the baseline,
    // or a genuinely new app installed while closed would never flag.
    tracker.refresh({});
    QCOMPARE(cfg->group(QStringLiteral("NewApps")).readEntry("installedApps", QStringList()).size(), 2);
}

QTEST_GUILESS_MAIN(TestNewAppsTracker)
#include "test_newappstracker.moc"
