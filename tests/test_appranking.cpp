/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppRanking: the favourites keep their order, a search ranks by relevance
    with favourites, preferred and default apps and usage as tie-breaks, and
    the sort modes order by name, launch count or category.
*/

#include "appranking.h"
#include "launchbookkeeping.h"
#include "stubappmodel.h"

#include <QTest>

class TestAppRanking : public QObject
{
    Q_OBJECT

private:
    StubAppModel m_model;
    LaunchBookkeeping m_book;

    bool before(const AppRanking &ranking, int left, int right, const AppRanking::Order &order)
    {
        return ranking.lessThan(m_model.index(left, 0), m_model.index(right, 0), order, m_book);
    }

private Q_SLOTS:
    void init()
    {
        // Rows: 0 Alpha (Office), 1 Beta (Games), 2 Terminal Tool (System).
        m_model.setApps({
            {QStringLiteral("Alpha"), {}, {}, {QStringLiteral("Office")}, {}, QStringLiteral("a"), {}, {}, {}},
            {QStringLiteral("Beta"), {}, {}, {QStringLiteral("Games")}, {}, QStringLiteral("b"), {}, {}, {}},
            {QStringLiteral("Terminal Tool"), {}, {}, {QStringLiteral("System")}, QStringLiteral("Terminal"), QStringLiteral("t"), {}, {}, {}},
        });
        m_book = LaunchBookkeeping();
    }

    void sortModes()
    {
        AppRanking ranking;
        QVERIFY(before(ranking, 0, 1, {}));
        m_book.bumpLaunch(QStringLiteral("b"));
        ranking.invalidate(); // the counts changed, as the model tells it
        AppRanking::Order mostUsed;
        mostUsed.sortMode = AppRanking::MostUsed;
        QVERIFY(before(ranking, 1, 0, mostUsed));
        AppRanking::Order byCategory;
        byCategory.sortMode = AppRanking::ByCategory;
        QVERIFY(before(ranking, 1, 0, byCategory)); // Games < Office
    }

    void favouritesKeepTheirOrder()
    {
        AppRanking ranking;
        QVERIFY(ranking.setFavorites({QStringLiteral("b"), QStringLiteral("a")}));
        QVERIFY(!ranking.setFavorites({QStringLiteral("b"), QStringLiteral("a")}));
        AppRanking::Order favourites;
        favourites.favoritesOnly = true;
        QVERIFY(before(ranking, 1, 0, favourites));
        QVERIFY(before(ranking, 0, 2, favourites)); // a non-favourite goes last
        favourites.favoritesAlphabetical = true;
        QVERIFY(before(ranking, 0, 1, favourites));
    }

    void searchRanksPreferredAppsFirst()
    {
        AppRanking ranking;
        AppRanking::Order search;
        search.query = QStringLiteral("t");
        // "Terminal Tool" starts with the query; Beta only contains it.
        QVERIFY(before(ranking, 2, 1, search));
        // Within the same tier, a preferred app outranks a default one.
        m_model.setApps({
            {QStringLiteral("Tea"), {}, {}, {}, {}, QStringLiteral("x"), {}, {}, {}},
            {QStringLiteral("Toast"), {}, {}, {}, {}, QStringLiteral("y"), {}, {}, {}},
        });
        ranking.invalidate();
        QVERIFY(before(ranking, 0, 1, search));
        QVERIFY(ranking.setDefaultApps({QStringLiteral("x")}));
        QVERIFY(ranking.setPreferredApps({QStringLiteral("y")}));
        QVERIFY(before(ranking, 1, 0, search));
    }

    void frecencyStandsInForLaunchCounts()
    {
        m_model.setApps({
            {QStringLiteral("Tea"), {}, {}, {}, {}, QStringLiteral("x"), {}, {}, {}},
            {QStringLiteral("Toast"), {}, {}, {}, {}, QStringLiteral("y"), {}, {}, {}},
        });
        AppRanking ranking;
        AppRanking::Order search;
        search.query = QStringLiteral("t");
        m_book.bumpLaunch(QStringLiteral("x"));
        QVERIFY(before(ranking, 0, 1, search));
        QVERIFY(ranking.setFrecencyScores({{QStringLiteral("y"), 5}}));
        QVERIFY(before(ranking, 0, 1, search)); // frecency not in use yet
        QVERIFY(ranking.setUseFrecency(true));
        QVERIFY(before(ranking, 1, 0, search));
    }
};

QTEST_GUILESS_MAIN(TestAppRanking)

#include "test_appranking.moc"
