/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for LaunchBookkeeping: the hidden/favorite/recent/known state
    and launch counts extracted from AppFilterModel.
*/

#include <QTest>

#include "launchbookkeeping.h"

class TestLaunchBookkeeping : public QObject
{
    Q_OBJECT
private slots:
    void hide_addsAndDedups();
    void unhide_removes();
    void setHidden_detectsNoChange();
    void favorites_trackPositions();
    void recent_prependsCapsDedups();
    void known_addAndIsNew();
    void launchCounts_mapRoundtripAndBump();
};

void TestLaunchBookkeeping::hide_addsAndDedups()
{
    LaunchBookkeeping b;
    QVERIFY(b.hide(QStringLiteral("a.desktop")));
    QVERIFY(b.isHidden(QStringLiteral("a.desktop")));
    QVERIFY(!b.hide(QStringLiteral("a.desktop"))); // duplicate
    QVERIFY(!b.hide(QString())); // empty
    QCOMPARE(b.hidden(), QStringList{QStringLiteral("a.desktop")});
    QVERIFY(!b.isHidden(QString()));
}

void TestLaunchBookkeeping::unhide_removes()
{
    LaunchBookkeeping b;
    b.setHidden({QStringLiteral("a.desktop"), QStringLiteral("b.desktop")});
    QVERIFY(b.unhide(QStringLiteral("a.desktop")));
    QVERIFY(!b.isHidden(QStringLiteral("a.desktop")));
    QVERIFY(b.isHidden(QStringLiteral("b.desktop")));
    QVERIFY(!b.unhide(QStringLiteral("a.desktop"))); // already gone
}

void TestLaunchBookkeeping::setHidden_detectsNoChange()
{
    LaunchBookkeeping b;
    QVERIFY(b.setHidden({QStringLiteral("a.desktop")}));
    QVERIFY(!b.setHidden({QStringLiteral("a.desktop")})); // same → no change
    QVERIFY(b.setHidden({QStringLiteral("b.desktop")}));
    QVERIFY(!b.isHidden(QStringLiteral("a.desktop")));
}

void TestLaunchBookkeeping::favorites_trackPositions()
{
    LaunchBookkeeping b;
    b.setFavorites({QStringLiteral("a.desktop"), QStringLiteral("b.desktop"), QStringLiteral("c.desktop")});
    QVERIFY(b.isFavorite(QStringLiteral("b.desktop")));
    QCOMPARE(b.favoritePosition(QStringLiteral("a.desktop"), -1), 0);
    QCOMPARE(b.favoritePosition(QStringLiteral("c.desktop"), -1), 2);
    QCOMPARE(b.favoritePosition(QStringLiteral("missing"), 999), 999);
}

void TestLaunchBookkeeping::recent_prependsCapsDedups()
{
    LaunchBookkeeping b;
    b.recordRecent(QStringLiteral("a.desktop"), 3);
    b.recordRecent(QStringLiteral("b.desktop"), 3);
    b.recordRecent(QStringLiteral("c.desktop"), 3);
    b.recordRecent(QStringLiteral("d.desktop"), 3); // caps to 3, drops oldest (a)
    QCOMPARE(b.recent(), QStringList({QStringLiteral("d.desktop"), QStringLiteral("c.desktop"), QStringLiteral("b.desktop")}));
    b.recordRecent(QStringLiteral("b.desktop"), 3); // re-launch moves to front
    QCOMPARE(b.recent(), QStringList({QStringLiteral("b.desktop"), QStringLiteral("d.desktop"), QStringLiteral("c.desktop")}));
    QVERIFY(b.isRecent(QStringLiteral("b.desktop")));
    QVERIFY(b.hasRecent());
}

void TestLaunchBookkeeping::known_addAndIsNew()
{
    LaunchBookkeeping b;
    QVERIFY(!b.isNew(QStringLiteral("x.desktop"))); // empty known set → nothing is "new"
    b.setKnown({QStringLiteral("a.desktop")});
    QVERIFY(b.isNew(QStringLiteral("x.desktop"))); // not known → new
    QVERIFY(!b.isNew(QStringLiteral("a.desktop"))); // known → not new
    QVERIFY(b.addKnown(QStringLiteral("x.desktop")));
    QVERIFY(!b.addKnown(QStringLiteral("x.desktop"))); // duplicate
    QVERIFY(!b.isNew(QStringLiteral("x.desktop")));
}

void TestLaunchBookkeeping::launchCounts_mapRoundtripAndBump()
{
    LaunchBookkeeping b;
    b.setLaunchCountsFromMap({{QStringLiteral("a.desktop"), 3}, {QStringLiteral("b.desktop"), 1}});
    QCOMPARE(b.launchCount(QStringLiteral("a.desktop")), 3);
    QCOMPARE(b.launchCount(QStringLiteral("missing")), 0);
    b.bumpLaunch(QStringLiteral("a.desktop"));
    b.bumpLaunch(QStringLiteral("c.desktop"));
    QCOMPARE(b.launchCount(QStringLiteral("a.desktop")), 4);
    QCOMPARE(b.launchCount(QStringLiteral("c.desktop")), 1);
    const QVariantMap m = b.launchCountsMap();
    QCOMPARE(m.value(QStringLiteral("a.desktop")).toInt(), 4);
    QCOMPARE(m.value(QStringLiteral("b.desktop")).toInt(), 1);

    // Re-setting the same map reports no change (lets the model skip the
    // emit/writeback on every open); a different map reports changed.
    const QVariantMap same = b.launchCountsMap();
    QVERIFY(!b.setLaunchCountsFromMap(same));
    QVERIFY(b.setLaunchCountsFromMap({{QStringLiteral("a.desktop"), 99}}));
}

QTEST_GUILESS_MAIN(TestLaunchBookkeeping)
#include "test_launchbookkeeping.moc"
