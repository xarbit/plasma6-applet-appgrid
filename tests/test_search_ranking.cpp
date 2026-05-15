/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Verifies search relevance ordering: prefix > substring > generic > keyword.
*/

#include <QTest>

#include "appfiltermodel.h"
#include "stubappmodel.h"

class TestSearchRanking : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void init();
    void prefixBeatsSubstring();
    void substringBeatsGeneric();
    void genericBeatsKeyword();
    void launchCountTiebreaksWithinTier();
    void emptySearchUsesAlphabetical();
    void defaultAppBeatsNonDefaultInSameTier();
    void launchCountStillBeatsDefaultAcrossTiers();
    void mostUsedJumpsOneTierUp();
    void mostUsedCannotJumpTwoTiers();
    void zeroCountDoesNotCrossTier();

private:
    QString nameAt(int proxyRow) const;
    StubAppModel m_source;
    AppFilterModel m_filter;
};

void TestSearchRanking::initTestCase()
{
    m_filter.setSourceModel(&m_source);
}

void TestSearchRanking::init()
{
    m_source.setApps({});
    m_filter.setSearchText(QString());
    m_filter.setFilterCategory(QString());
    m_filter.setHiddenApps({});
    m_filter.setFavoriteApps({});
    m_filter.setRecentApps({});
    m_filter.setShowFavoritesOnly(false);
    m_filter.setSortMode(AppFilterModel::Alphabetical);
    m_filter.setLaunchCountsMap({});
    m_filter.setDefaultApps({});
}

QString TestSearchRanking::nameAt(int row) const
{
    return m_filter.index(row, 0).data(AppModel::NameRole).toString();
}

void TestSearchRanking::prefixBeatsSubstring()
{
    m_source.setApps({
        {QStringLiteral("Blender"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Tableau"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}}, // contains "able"
        {QStringLiteral("Able-Editor"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}}, // prefix "Able"
    });
    m_filter.setSearchText(QStringLiteral("able"));
    QCOMPARE(m_filter.count(), 2);
    QCOMPARE(nameAt(0), QStringLiteral("Able-Editor")); // prefix wins
    QCOMPARE(nameAt(1), QStringLiteral("Tableau"));
}

void TestSearchRanking::substringBeatsGeneric()
{
    m_source.setApps({
        {QStringLiteral("Firefox"), {}, {}, {}, QStringLiteral("Web Browser"), QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Konqueror"), {}, {}, {}, QStringLiteral("Web Browser"), QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("ProBrowse"), {}, {}, {}, QStringLiteral("File Manager"), QStringLiteral("c"), {}, {}, {}}, // name substring
    });
    m_filter.setSearchText(QStringLiteral("brow"));
    QCOMPARE(m_filter.count(), 3);
    QCOMPARE(nameAt(0), QStringLiteral("ProBrowse")); // substring beats generic
}

void TestSearchRanking::genericBeatsKeyword()
{
    m_source.setApps({
        {QStringLiteral("Foo"), {}, {}, {}, QStringLiteral("Photo Editor"), QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Bar"), {}, {}, {}, {}, QStringLiteral("b"), {QStringLiteral("photo")}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("photo"));
    QCOMPARE(m_filter.count(), 2);
    QCOMPARE(nameAt(0), QStringLiteral("Foo")); // generic beats keyword
}

void TestSearchRanking::launchCountTiebreaksWithinTier()
{
    m_source.setApps({
        {QStringLiteral("Editor A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Editor B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("Editor C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("b")] = 50;
    counts[QStringLiteral("a")] = 10;
    counts[QStringLiteral("c")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("editor"));
    QCOMPARE(m_filter.count(), 3);
    QCOMPARE(nameAt(0), QStringLiteral("Editor B")); // highest launch count first
    QCOMPARE(nameAt(1), QStringLiteral("Editor A"));
    QCOMPARE(nameAt(2), QStringLiteral("Editor C"));
    m_filter.setSearchText(QString());
    m_filter.setLaunchCountsMap({});
}

void TestSearchRanking::emptySearchUsesAlphabetical()
{
    m_source.setApps({
        {QStringLiteral("Zebra"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Apple"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("Mango"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSearchText(QString());
    QCOMPARE(m_filter.count(), 3);
    QCOMPARE(nameAt(0), QStringLiteral("Apple"));
    QCOMPARE(nameAt(1), QStringLiteral("Mango"));
    QCOMPARE(nameAt(2), QStringLiteral("Zebra"));
}

void TestSearchRanking::defaultAppBeatsNonDefaultInSameTier()
{
    // Both names start with "fire" — same relevance tier (prefix).
    // Firefox is the mime default; FireFly is not. Firefox should win.
    m_source.setApps({
        {QStringLiteral("FireFly"), {}, {}, {}, {}, QStringLiteral("firefly.desktop"), {}, {}, {}},
        {QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("firefox.desktop"), {}, {}, {}},
    });
    m_filter.setDefaultApps({QStringLiteral("firefox.desktop")});
    m_filter.setSearchText(QStringLiteral("fire"));
    QCOMPARE(nameAt(0), QStringLiteral("Firefox"));
    QCOMPARE(nameAt(1), QStringLiteral("FireFly"));
}

void TestSearchRanking::launchCountStillBeatsDefaultAcrossTiers()
{
    // FireFly has higher relevance (name prefix), Firefox only matches via
    // generic name. Even though Firefox is the default, the better tier
    // (prefix) wins.
    m_source.setApps({
        {QStringLiteral("FireFly"), {}, {}, {}, QStringLiteral("Insect Sim"),
         QStringLiteral("firefly.desktop"), {}, {}, {}},
        {QStringLiteral("Mozilla"), {}, {}, {}, QStringLiteral("Web Browser, fire-tested"),
         QStringLiteral("firefox.desktop"), {}, {}, {}},
    });
    m_filter.setDefaultApps({QStringLiteral("firefox.desktop")});
    m_filter.setSearchText(QStringLiteral("fire"));
    QCOMPARE(nameAt(0), QStringLiteral("FireFly")); // prefix tier wins over default boost
}

void TestSearchRanking::mostUsedJumpsOneTierUp()
{
    // Ghostty matches "terminal" only via keyword (tier 3), Alacritty via
    // generic name (tier 2). Ghostty is used much more — it should win.
    m_source.setApps({
        {QStringLiteral("Alacritty"), {}, {}, {},
         QStringLiteral("Terminal Emulator"), QStringLiteral("alacritty.desktop"),
         {}, {}, {}},
        {QStringLiteral("Ghostty"), {}, {}, {},
         QStringLiteral("GPU-Accelerated Console"), QStringLiteral("ghostty.desktop"),
         {QStringLiteral("terminal")}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("ghostty.desktop")] = 50;
    counts[QStringLiteral("alacritty.desktop")] = 1;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("terminal"));
    QCOMPARE(m_filter.count(), 2);
    QCOMPARE(nameAt(0), QStringLiteral("Ghostty"));
    QCOMPARE(nameAt(1), QStringLiteral("Alacritty"));
}

void TestSearchRanking::mostUsedCannotJumpTwoTiers()
{
    // Calc has prefix match (tier 0). Calculator has only keyword match (tier 3).
    // Even with huge launch count, Calculator cannot skip two tiers — Calc wins.
    m_source.setApps({
        {QStringLiteral("Calc-Pro"), {}, {}, {}, {},
         QStringLiteral("calc-pro.desktop"), {}, {}, {}},
        {QStringLiteral("MathBox"), {}, {}, {}, {},
         QStringLiteral("mathbox.desktop"), {QStringLiteral("calc")}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("mathbox.desktop")] = 500;
    counts[QStringLiteral("calc-pro.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("calc"));
    QCOMPARE(nameAt(0), QStringLiteral("Calc-Pro"));
    QCOMPARE(nameAt(1), QStringLiteral("MathBox"));
}

void TestSearchRanking::zeroCountDoesNotCrossTier()
{
    // Both unused: tier order wins as normal.
    m_source.setApps({
        {QStringLiteral("Alacritty"), {}, {}, {},
         QStringLiteral("Terminal Emulator"), QStringLiteral("alacritty.desktop"),
         {}, {}, {}},
        {QStringLiteral("Ghostty"), {}, {}, {},
         QStringLiteral("GPU-Accelerated Console"), QStringLiteral("ghostty.desktop"),
         {QStringLiteral("terminal")}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("terminal"));
    QCOMPARE(nameAt(0), QStringLiteral("Alacritty")); // generic tier 2 beats keyword tier 3
}

QTEST_MAIN(TestSearchRanking)
#include "test_search_ranking.moc"
