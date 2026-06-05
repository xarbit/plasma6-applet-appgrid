/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for FrecencyScoring::scoresFromResources — the pure rank-scoring
    extracted from FrecencyProvider so it can be tested without a live KAStats
    database. Pins rank ordering, the org.kde. dual-spelling indexing, the
    never-demote-on-collision rule, and prefix filtering.
*/

#include <QTest>

#include "frecencyscoring.h"

class TestFrecencyScoring : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void rankScoreTopRowHighest();
    void indexesBothKdeSpellings();
    void neverDemotesHigherScore();
    void skipsNonApplicationResources();
    void emptyInputYieldsEmptyMap();
};

void TestFrecencyScoring::rankScoreTopRowHighest()
{
    const auto s = FrecencyScoring::scoresFromResources({
        QStringLiteral("applications:a.desktop"),
        QStringLiteral("applications:b.desktop"),
        QStringLiteral("applications:c.desktop"),
    });
    // Top row scores `count` (3), last scores 1.
    QCOMPARE(s.value(QStringLiteral("a.desktop")), 3);
    QCOMPARE(s.value(QStringLiteral("b.desktop")), 2);
    QCOMPARE(s.value(QStringLiteral("c.desktop")), 1);
}

void TestFrecencyScoring::indexesBothKdeSpellings()
{
    const auto s = FrecencyScoring::scoresFromResources({
        QStringLiteral("applications:org.kde.konsole.desktop"),
        QStringLiteral("applications:firefox.desktop"),
    });
    // org.kde.* row indexed under both the full and the bare spelling.
    QCOMPARE(s.value(QStringLiteral("org.kde.konsole.desktop")), 2);
    QCOMPARE(s.value(QStringLiteral("konsole.desktop")), 2);
    // bare row indexed under both the bare and the synthesised org.kde. form.
    QCOMPARE(s.value(QStringLiteral("firefox.desktop")), 1);
    QCOMPARE(s.value(QStringLiteral("org.kde.firefox.desktop")), 1);
}

void TestFrecencyScoring::neverDemotesHigherScore()
{
    // Two rows normalise to the same bare key "konsole.desktop": the higher
    // (earlier) row's score must win, not the later, lower one.
    const auto s = FrecencyScoring::scoresFromResources({
        QStringLiteral("applications:org.kde.konsole.desktop"), // score 2 → konsole.desktop
        QStringLiteral("applications:konsole.desktop"), // score 1 → konsole.desktop
    });
    QCOMPARE(s.value(QStringLiteral("konsole.desktop")), 2);
}

void TestFrecencyScoring::skipsNonApplicationResources()
{
    const auto s = FrecencyScoring::scoresFromResources({
        QStringLiteral("file:///home/u/doc.txt"),
        QStringLiteral("applications:a.desktop"),
    });
    QVERIFY(!s.contains(QStringLiteral("doc.txt")));
    // count is 2, the application row is at index 1 → score 2 - 1 = 1.
    QCOMPARE(s.value(QStringLiteral("a.desktop")), 1);
}

void TestFrecencyScoring::emptyInputYieldsEmptyMap()
{
    QVERIFY(FrecencyScoring::scoresFromResources({}).isEmpty());
}

QTEST_GUILESS_MAIN(TestFrecencyScoring)
#include "test_frecency_scoring.moc"
