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
    void keywordCannotLeapPastGenericMatch();
    void mostUsedCannotDethronePrefix();
    void wordBoundarySubstringBeatsMidword();
    void midwordSubstringCannotBeatGeneric();
    void midwordSubstringStaysBelowKeywordEvenWhenUsed();
    void zeroCountDoesNotCrossTier();
    void frecencyTiebreakReplacesLaunchCount();
    void frecencyFallsBackToLaunchCountWhenMapEmpty();
    void categoryMatchLandsInTier3();
    void pluralQueryReachesSingularCategory();

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
    // A word-boundary substring in the name (tier 1) beats a generic-name
    // match (tier 2). "Pro-Browse" has "Browse" at a word boundary (after
    // the hyphen); mid-word substrings would not qualify for tier 1 — see
    // midwordSubstringCannotBeatGeneric.
    m_source.setApps({
        {QStringLiteral("Firefox"), {}, {}, {}, QStringLiteral("Web Browser"), QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Konqueror"), {}, {}, {}, QStringLiteral("Web Browser"), QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("Pro-Browse"), {}, {}, {}, QStringLiteral("File Manager"), QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("brow"));
    QCOMPARE(m_filter.count(), 3);
    QCOMPARE(nameAt(0), QStringLiteral("Pro-Browse"));
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
    // Heavy-use promotion still spans the 3↔4 boundary: a frequently used
    // keyword match outranks a never-launched mid-word fallback. The 2↔3
    // boundary used to also promote — see keywordCannotLeapPastGenericMatch
    // for why it doesn't any more.
    m_source.setApps({
        // Mid-word "term" hit (tier 4): "Postermaker" has "term" mid-word.
        {QStringLiteral("Postermaker"), {}, {}, {}, {},
         QStringLiteral("postermaker.desktop"), {}, {}, {}},
        // Keyword "terminal" → tier 3 for query "term".
        {QStringLiteral("Ghostty"), {}, {}, {}, {},
         QStringLiteral("ghostty.desktop"),
         {QStringLiteral("terminal")}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("ghostty.desktop")] = 50;
    counts[QStringLiteral("postermaker.desktop")] = 1;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("term"));
    QCOMPARE(m_filter.count(), 2);
    QCOMPARE(nameAt(0), QStringLiteral("Ghostty"));
    QCOMPARE(nameAt(1), QStringLiteral("Postermaker"));
}

void TestSearchRanking::keywordCannotLeapPastGenericMatch()
{
    // Real-world regression: searching "games" surfaced Discover above Steam
    // because Discover lists "games" in its Keywords (tier 3) and is used
    // heavily, so the old ±1 promotion lifted it past Steam's Comment-fallback
    // generic-tier-2 match. Categories=Game on Steam reinforces the result.
    // Keep tier-3 keyword matches from leaping past tier-2 generic/Comment.
    m_source.setApps({
        // Steam: no GenericName → Comment fallback word-boundary "games" → tier 2.
        {QStringLiteral("Steam"), {}, {}, {QStringLiteral("Game")}, {},
         QStringLiteral("steam.desktop"), {},
         QStringLiteral("Application for managing and playing games on Steam"), {}},
        // Discover: Keywords mention games → tier 3, heavily used.
        {QStringLiteral("Discover"), {}, {}, {QStringLiteral("System")},
         QStringLiteral("Software Center"), QStringLiteral("discover.desktop"),
         {QStringLiteral("apps"), QStringLiteral("games"), QStringLiteral("flatpak")},
         QStringLiteral("Install and remove apps"), {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("discover.desktop")] = 500;
    counts[QStringLiteral("steam.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("games"));
    QCOMPARE(nameAt(0), QStringLiteral("Steam"));
    QCOMPARE(nameAt(1), QStringLiteral("Discover"));
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

void TestSearchRanking::mostUsedCannotDethronePrefix()
{
    // Terminal matches "ter" as a name-prefix (tier 0); Spotter matches it
    // only as a substring (tier 1). Even with overwhelming launch count on
    // Spotter, the prefix tier is inviolate — Terminal stays on top.
    m_source.setApps({
        {QStringLiteral("Spotter"), {}, {}, {}, {},
         QStringLiteral("spotter.desktop"), {}, {}, {}},
        {QStringLiteral("Terminal"), {}, {}, {}, {},
         QStringLiteral("terminal.desktop"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("spotter.desktop")] = 500;
    counts[QStringLiteral("terminal.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("ter"));
    QCOMPARE(nameAt(0), QStringLiteral("Terminal"));
    QCOMPARE(nameAt(1), QStringLiteral("Spotter"));
}

void TestSearchRanking::wordBoundarySubstringBeatsMidword()
{
    // "Library Manager" hits "lib" at a word boundary (start of name → tier 0
    // prefix). "Calibre" hits "lib" mid-word ("Ca**lib**re") → tier 4 fallback.
    // Library wins decisively.
    m_source.setApps({
        {QStringLiteral("Calibre"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Library Manager"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("lib"));
    QCOMPARE(nameAt(0), QStringLiteral("Library Manager"));
    QCOMPARE(nameAt(1), QStringLiteral("Calibre"));
}

void TestSearchRanking::midwordSubstringCannotBeatGeneric()
{
    // "ghostwriter" contains "ter" mid-word → tier 4 fallback. The other app
    // has "Terminal Emulator" as its generic name → tier 2. Generic wins.
    m_source.setApps({
        {QStringLiteral("ghostwriter"), {}, {}, {}, {},
         QStringLiteral("ghostwriter.desktop"), {}, {}, {}},
        {QStringLiteral("Alacritty"), {}, {}, {},
         QStringLiteral("Terminal Emulator"), QStringLiteral("alacritty.desktop"),
         {}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("ter"));
    QCOMPARE(nameAt(0), QStringLiteral("Alacritty"));
    QCOMPARE(nameAt(1), QStringLiteral("ghostwriter"));
}

void TestSearchRanking::midwordSubstringStaysBelowKeywordEvenWhenUsed()
{
    // ghostwriter is heavily launched and matches "ter" only mid-word
    // (tier 4 fallback). Ghostty matches via the "terminal" keyword (tier 3).
    // The fallback tier is inviolate from below — Ghostty still wins.
    m_source.setApps({
        {QStringLiteral("ghostwriter"), {}, {}, {}, {},
         QStringLiteral("ghostwriter.desktop"), {}, {}, {}},
        {QStringLiteral("Ghostty"), {}, {}, {},
         QStringLiteral("GPU-Accelerated Console"),
         QStringLiteral("ghostty.desktop"),
         {QStringLiteral("terminal")}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("ghostwriter.desktop")] = 500;
    counts[QStringLiteral("ghostty.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("ter"));
    QCOMPARE(nameAt(0), QStringLiteral("Ghostty"));
    QCOMPARE(nameAt(1), QStringLiteral("ghostwriter"));
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

void TestSearchRanking::frecencyTiebreakReplacesLaunchCount()
{
    // Same tier (both prefix). Launch counts say A wins; flipping the
    // opt-in frecency map should make B win since the search tiebreak now
    // reads frecency scores instead of launch counts.
    m_source.setApps({
        {QStringLiteral("Kate-A"), {}, {}, {}, {}, QStringLiteral("kate-a.desktop"), {}, {}, {}},
        {QStringLiteral("Kate-B"), {}, {}, {}, {}, QStringLiteral("kate-b.desktop"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("kate-a.desktop")] = 50;
    counts[QStringLiteral("kate-b.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("kate"));
    QCOMPARE(nameAt(0), QStringLiteral("Kate-A"));

    QHash<QString, int> frec;
    frec.insert(QStringLiteral("kate-a.desktop"), 0);
    frec.insert(QStringLiteral("kate-b.desktop"), 100);
    m_filter.setFrecencyScores(frec);
    m_filter.setSearchUsesFrecency(true);
    QCOMPARE(nameAt(0), QStringLiteral("Kate-B"));

    m_filter.setSearchUsesFrecency(false);
    m_filter.setFrecencyScores({});
}

void TestSearchRanking::frecencyFallsBackToLaunchCountWhenMapEmpty()
{
    // Frecency toggled on but no scores fetched yet (KAStats may not have
    // populated). Ranking must keep using launch counts instead of treating
    // every app as zero-frecency.
    m_source.setApps({
        {QStringLiteral("Kate-A"), {}, {}, {}, {}, QStringLiteral("kate-a.desktop"), {}, {}, {}},
        {QStringLiteral("Kate-B"), {}, {}, {}, {}, QStringLiteral("kate-b.desktop"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("kate-a.desktop")] = 50;
    counts[QStringLiteral("kate-b.desktop")] = 0;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchUsesFrecency(true);
    m_filter.setFrecencyScores({});
    m_filter.setSearchText(QStringLiteral("kate"));
    QCOMPARE(nameAt(0), QStringLiteral("Kate-A"));

    m_filter.setSearchUsesFrecency(false);
}

void TestSearchRanking::categoryMatchLandsInTier3()
{
    // Categories are searched at tier 3. "Empire" has no name/generic/keyword
    // hit for "game", only Categories=Game. A mid-word "game" in another app's
    // name lands at tier 4 — tier 3 ranks above.
    m_source.setApps({
        {QStringLiteral("Mygamestuff"), {}, {}, {}, {},
         QStringLiteral("a"), {}, {}, {}},                                        // tier 4 (mid-word)
        {QStringLiteral("Empire"), {}, {}, {QStringLiteral("Game")}, {},
         QStringLiteral("b"), {}, {}, {}},                                        // tier 3 (category)
    });
    m_filter.setSearchText(QStringLiteral("game"));
    QCOMPARE(m_filter.count(), 2);
    QCOMPARE(nameAt(0), QStringLiteral("Empire"));
    QCOMPARE(nameAt(1), QStringLiteral("Mygamestuff"));
}

void TestSearchRanking::pluralQueryReachesSingularCategory()
{
    // Typing "games" should still find an app whose Categories list is "Game"
    // — the naive singularize() helper strips the trailing s for the filter +
    // category check. Konsole has nothing matching "games" or "game" → drops.
    m_source.setApps({
        {QStringLiteral("Empire"), {}, {}, {QStringLiteral("Game")}, {},
         QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Konsole"), {}, {}, {QStringLiteral("System")},
         QStringLiteral("Terminal"), QStringLiteral("b"), {}, {}, {}},
    });
    m_filter.setSearchText(QStringLiteral("games"));
    QCOMPARE(m_filter.count(), 1);
    QCOMPARE(nameAt(0), QStringLiteral("Empire"));
}

QTEST_MAIN(TestSearchRanking)
#include "test_search_ranking.moc"
