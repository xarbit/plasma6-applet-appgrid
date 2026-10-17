/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Verifies search relevance ordering: prefix > substring > generic > keyword.
*/

#include <QTest>

#include <algorithm>

#include "appfiltermodel.h"
#include "searchranking.h"
#include "stubappmodel.h"

class TestSearchRanking : public QObject {
    Q_OBJECT
private Q_SLOTS:
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

    // Direct unit tests for the pure SearchRanking helpers.
    void relevance_classifiesEachTier();
    void singularize_rules();
    void containsAtWordBoundary_rules();
    void completionWord_rules();
    void compare_rules();
    void compare_isStrictWeakOrdering();
    void compare_terminalSearch_data();
    void compare_terminalSearch();
    void favoriteRanksFirstInTier();
    void usageBeatsMimeDefaultInSameTier();

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

void TestSearchRanking::relevance_classifiesEachTier()
{
    using namespace SearchRanking;
    QCOMPARE(relevance(QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("fire")), TierNamePrefix);
    QCOMPARE(relevance(QStringLiteral("Mozilla Firefox"), {}, {}, {}, {}, QStringLiteral("fire")), TierNameWordBoundary);
    QCOMPARE(relevance(QStringLiteral("Kate"), QStringLiteral("Text Editor"), {}, {}, {}, QStringLiteral("editor")), TierGeneric);
    // Comment is the tier-2 source only when GenericName is empty.
    QCOMPARE(relevance(QStringLiteral("Foo"), {}, QStringLiteral("A music player"), {}, {}, QStringLiteral("music")), TierGeneric);
    QCOMPARE(relevance(QStringLiteral("Kate"), {}, {}, {QStringLiteral("ide")}, {}, QStringLiteral("ide")), TierKeyword);
    QCOMPARE(relevance(QStringLiteral("ghostwriter"), {}, {}, {}, {}, QStringLiteral("ter")), TierNameMidword);
    QCOMPARE(relevance(QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("zzz")), TierNoMatch);
    QCOMPARE(relevance(QStringLiteral("Kate"), {}, {}, {}, {}, QString()), TierNoMatch);
}

void TestSearchRanking::singularize_rules()
{
    QCOMPARE(SearchRanking::singularize(QStringLiteral("games")), QStringLiteral("game"));
    QVERIFY(SearchRanking::singularize(QStringLiteral("os")).isEmpty()); // shorter than 4 chars
    QVERIFY(SearchRanking::singularize(QStringLiteral("game")).isEmpty()); // no trailing 's'
}

void TestSearchRanking::containsAtWordBoundary_rules()
{
    QVERIFY(SearchRanking::containsAtWordBoundary(QStringLiteral("Mozilla Firefox"), QStringLiteral("fire")));
    QVERIFY(!SearchRanking::containsAtWordBoundary(QStringLiteral("ghostwriter"), QStringLiteral("ter")));
    QVERIFY(!SearchRanking::containsAtWordBoundary(QStringLiteral("abc"), QString()));
}

void TestSearchRanking::completionWord_rules()
{
    using namespace SearchRanking;
    // First word starting with the query, original casing, longer than query.
    QCOMPARE(completionWord(QStringLiteral("Terminal emulator"), QStringLiteral("te")), QStringLiteral("Terminal"));
    QCOMPARE(completionWord(QStringLiteral("Web Browser"), QStringLiteral("br")), QStringLiteral("Browser"));
    QCOMPARE(completionWord(QStringLiteral("Ghostty"), QStringLiteral("gh")), QStringLiteral("Ghostty"));
    // Case-insensitive match.
    QCOMPARE(completionWord(QStringLiteral("Firefox"), QStringLiteral("FIRE")), QStringLiteral("Firefox"));
    // No match / nothing to add / empty input.
    QVERIFY(completionWord(QStringLiteral("Terminal"), QStringLiteral("xyz")).isEmpty());
    QVERIFY(completionWord(QStringLiteral("Terminal"), QStringLiteral("terminal")).isEmpty());
    QVERIFY(completionWord(QString(), QStringLiteral("te")).isEmpty());
    QVERIFY(completionWord(QStringLiteral("Terminal"), QString()).isEmpty());
}

void TestSearchRanking::compare_rules()
{
    using namespace SearchRanking;
    struct R {
        int relevance;
        int usage = 0;
        bool favorite = false;
        bool preferred = false;
        bool isDefault = false;
    };
    const auto rank = [](R r) {
        return ResultRank{r.relevance, r.usage, r.favorite, r.preferred, r.isDefault};
    };
    const auto cmp = [&](R a, R b) {
        return compare(rank(a), rank(b));
    };
    // A better tier wins.
    QVERIFY(cmp({TierNamePrefix}, {TierNameWordBoundary}) < 0);
    QVERIFY(cmp({TierKeyword}, {TierGeneric}) > 0);
    // A result may climb one tier, name word-boundary <-> generic only ...
    QVERIFY(cmp({TierGeneric, 10}, {TierNameWordBoundary, 0}) < 0);
    QVERIFY(cmp({TierKeyword, 10}, {TierGeneric, 0}) > 0); // keyword vs generic: blocked
    // ... never two tiers, never across the endpoint tiers.
    QVERIFY(cmp({TierKeyword, 10}, {TierNameWordBoundary, 0}) > 0);
    QVERIFY(cmp({TierNameWordBoundary, 10}, {TierNamePrefix, 0}) > 0);
    QVERIFY(cmp({TierNameMidword, 10}, {TierKeyword, 0}) > 0);
    // In a tier: starred favourite, then role default, then usage, then mime default.
    QVERIFY(cmp({TierGeneric, 0, true}, {TierGeneric, 99, false, true, true}) < 0);
    QVERIFY(cmp({TierGeneric, 0, false, true}, {TierGeneric, 99, false, false, true}) < 0);
    QVERIFY(cmp({TierGeneric, 5}, {TierGeneric, 2, false, false, true}) < 0);
    QVERIFY(cmp({TierGeneric, 2, false, false, true}, {TierGeneric, 2}) < 0);
    // A full tie is left to the name.
    QCOMPARE(cmp({TierGeneric, 3, true, true}, {TierGeneric, 3, true, true}), 0);
}

// std::stable_sort (used by QSortFilterProxyModel) needs a strict weak
// ordering; the one-tier promotion is exactly the kind of rule that could
// make it cyclic. Check every combination on a grid of ranks.
void TestSearchRanking::compare_isStrictWeakOrdering()
{
    using namespace SearchRanking;
    QList<ResultRank> ranks;
    for (int relevance = TierNamePrefix; relevance <= TierNameMidword; ++relevance) {
        for (int usage : {0, 1, 5}) {
            for (int flags = 0; flags < 8; ++flags) {
                ranks.append({relevance, usage, (flags & 1) != 0, (flags & 2) != 0, (flags & 4) != 0});
            }
        }
    }
    const auto less = [](const ResultRank &a, const ResultRank &b) {
        return compare(a, b) < 0;
    };
    const auto equivalent = [&](const ResultRank &a, const ResultRank &b) {
        return !less(a, b) && !less(b, a);
    };
    for (const ResultRank &a : ranks) {
        QVERIFY(!less(a, a));
        for (const ResultRank &b : ranks) {
            QCOMPARE(compare(a, b) < 0, compare(b, a) > 0);
            for (const ResultRank &c : ranks) {
                if (less(a, b) && less(b, c)) {
                    QVERIFY2(less(a, c), "less is not transitive");
                }
                if (equivalent(a, b) && equivalent(b, c)) {
                    QVERIFY2(equivalent(a, c), "equivalence is not transitive");
                }
            }
        }
    }
}

// Typing "terminal" with real-world names: the tiers come from relevance(),
// the order from compare() with the name as tiebreak, as in AppFilterModel.
void TestSearchRanking::compare_terminalSearch_data()
{
    QTest::addColumn<QString>("starred");
    QTest::addColumn<QString>("roleDefault");
    QTest::addColumn<QStringList>("expected");
    // Ghostty is starred, the default terminal and the most used.
    QTest::newRow("favourite, default and most used")
        << QStringLiteral("Ghostty") << QStringLiteral("Ghostty")
        << QStringList{QStringLiteral("Ghostty"), QStringLiteral("Konsole"), QStringLiteral("Alacritty"), QStringLiteral("COSMIC Terminal")};
    // A starred terminal beats the default and the most used one.
    QTest::newRow("starred beats default and usage")
        << QStringLiteral("Alacritty") << QStringLiteral("Ghostty")
        << QStringList{QStringLiteral("Alacritty"), QStringLiteral("Ghostty"), QStringLiteral("Konsole"), QStringLiteral("COSMIC Terminal")};
    // Nothing starred: the default terminal beats the more used one.
    QTest::newRow("default beats usage")
        << QString() << QStringLiteral("Konsole")
        << QStringList{QStringLiteral("Konsole"), QStringLiteral("Ghostty"), QStringLiteral("Alacritty"), QStringLiteral("COSMIC Terminal")};
}

void TestSearchRanking::compare_terminalSearch()
{
    QFETCH(QString, starred);
    QFETCH(QString, roleDefault);
    QFETCH(QStringList, expected);
    using namespace SearchRanking;
    struct App {
        QString name;
        QString genericName;
        int launches;
    };
    const QList<App> apps{
        {QStringLiteral("COSMIC Terminal"), QStringLiteral("Terminal Emulator"), 1},
        {QStringLiteral("Alacritty"), QStringLiteral("Terminal"), 3},
        {QStringLiteral("Konsole"), QStringLiteral("Terminal Emulator"), 12},
        {QStringLiteral("Ghostty"), QStringLiteral("Terminal Emulator"), 72},
    };
    const QString query = QStringLiteral("terminal");
    const auto rankOf = [&](const App &app) {
        return ResultRank{relevance(app.name, app.genericName, {}, {}, {}, query), app.launches, app.name == starred, app.name == roleDefault, false};
    };
    QList<App> sorted = apps;
    std::stable_sort(sorted.begin(), sorted.end(), [&](const App &a, const App &b) {
        if (const int order = compare(rankOf(a), rankOf(b)); order != 0) {
            return order < 0;
        }
        return QString::localeAwareCompare(a.name, b.name) < 0;
    });
    QStringList names;
    for (const App &app : sorted) {
        names.append(app.name);
    }
    QCOMPARE(names, expected);
}

// Through the model: a starred favourite ranks first in its tier, and the
// ranking follows the favourites when they change.
void TestSearchRanking::favoriteRanksFirstInTier()
{
    m_source.setApps({
        {QStringLiteral("Editor A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Editor B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("b")] = 50;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSearchText(QStringLiteral("editor"));
    QCOMPARE(nameAt(0), QStringLiteral("Editor B")); // most used

    m_filter.setFavoriteApps({QStringLiteral("a")});
    QCOMPARE(nameAt(0), QStringLiteral("Editor A")); // starred beats usage
    m_filter.setFavoriteApps({});
    QCOMPARE(nameAt(0), QStringLiteral("Editor B"));
    m_filter.setSearchText(QString());
    m_filter.setLaunchCountsMap({});
}

// Usage beats a mime default in the same tier (the default only breaks ties).
void TestSearchRanking::usageBeatsMimeDefaultInSameTier()
{
    m_source.setApps({
        {QStringLiteral("FireFly"), {}, {}, {}, {}, QStringLiteral("firefly.desktop"), {}, {}, {}},
        {QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("firefox.desktop"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("firefly.desktop")] = 5;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setDefaultApps({QStringLiteral("firefox.desktop")});
    m_filter.setSearchText(QStringLiteral("fire"));
    QCOMPARE(nameAt(0), QStringLiteral("FireFly"));
    m_filter.setSearchText(QString());
    m_filter.setLaunchCountsMap({});
    m_filter.setDefaultApps({});
}

QTEST_MAIN(TestSearchRanking)
#include "test_search_ranking.moc"
