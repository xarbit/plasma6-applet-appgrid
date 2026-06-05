/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Verifies lessThan() ordering per sort mode.
*/

#include <QTest>

#include "appfiltermodel.h"
#include "stubappmodel.h"

class TestSort : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void init();
    void alphabeticalSortCaseInsensitive();
    void mostUsedSortsByLaunchCount();
    void mostUsedFallsBackToNameOnTie();
    void mostUsedRerankAfterSingleLaunch();
    void byCategorySortsByCategoryThenName();
    void favoritesOnlyPreservesOrder();
    void favoritesOnlySortsAlphabeticallyWhenEnabled();

private:
    QStringList nameOrder() const;
    StubAppModel m_source;
    AppFilterModel m_filter;
};

void TestSort::initTestCase()
{
    m_filter.setSourceModel(&m_source);
}

void TestSort::init()
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
    m_filter.setSortFavoritesAlphabetically(false);
}

QStringList TestSort::nameOrder() const
{
    QStringList names;
    for (int i = 0; i < m_filter.count(); ++i)
        names << m_filter.index(i, 0).data(AppModel::NameRole).toString();
    return names;
}

void TestSort::alphabeticalSortCaseInsensitive()
{
    m_source.setApps({
        {QStringLiteral("banana"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Apple"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("cherry"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSortMode(AppFilterModel::Alphabetical);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("Apple"), QStringLiteral("banana"), QStringLiteral("cherry")}));
}

void TestSort::mostUsedSortsByLaunchCount()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    QVariantMap counts;
    counts[QStringLiteral("b")] = 100;
    counts[QStringLiteral("c")] = 50;
    counts[QStringLiteral("a")] = 10;
    m_filter.setLaunchCountsMap(counts);
    m_filter.setSortMode(AppFilterModel::MostUsed);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("B"), QStringLiteral("C"), QStringLiteral("A")}));
}

void TestSort::mostUsedFallsBackToNameOnTie()
{
    m_source.setApps({
        {QStringLiteral("Charlie"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Alpha"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("Bravo"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setLaunchCountsMap({}); // all zero
    m_filter.setSortMode(AppFilterModel::MostUsed);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("Alpha"), QStringLiteral("Bravo"), QStringLiteral("Charlie")}));
}

void TestSort::mostUsedRerankAfterSingleLaunch()
{
    // Regression: launching an app must re-rank it on the FIRST launch, not the
    // second. The bug was recordRecentLaunch() re-sorting before bumping the
    // count, so the sort read the pre-launch value.
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setLaunchCountsMap({}); // all zero → alphabetical: A, B, C
    m_filter.setSortMode(AppFilterModel::MostUsed);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("A"), QStringLiteral("B"), QStringLiteral("C")}));

    m_filter.recordRecentLaunch(QStringLiteral("c")); // one launch
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("C"), QStringLiteral("A"), QStringLiteral("B")}));
}

void TestSort::byCategorySortsByCategoryThenName()
{
    m_source.setApps({
        {QStringLiteral("Zen"), {}, {}, {QStringLiteral("Utility")}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Apex"), {}, {}, {QStringLiteral("Utility")}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("Kate"), {}, {}, {QStringLiteral("Development")}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSortMode(AppFilterModel::ByCategory);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("Kate"),  // Development first
        QStringLiteral("Apex"),  // Utility, then alphabetical within category
        QStringLiteral("Zen")}));
}

void TestSort::favoritesOnlyPreservesOrder()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSortMode(AppFilterModel::Alphabetical);
    m_filter.setFavoriteApps({QStringLiteral("c"), QStringLiteral("a"), QStringLiteral("b")});
    m_filter.setShowFavoritesOnly(true);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("C"), QStringLiteral("A"), QStringLiteral("B")}));
}

void TestSort::favoritesOnlySortsAlphabeticallyWhenEnabled()
{
    m_source.setApps({
        {QStringLiteral("Zebra"), {}, {}, {}, {}, QStringLiteral("z"), {}, {}, {}},
        {QStringLiteral("Apple"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("Mango"), {}, {}, {}, {}, QStringLiteral("m"), {}, {}, {}},
    });
    // Manual order says: z, a, m
    m_filter.setFavoriteApps({QStringLiteral("z"), QStringLiteral("a"), QStringLiteral("m")});
    m_filter.setShowFavoritesOnly(true);
    m_filter.setSortFavoritesAlphabetically(true);
    QCOMPARE(nameOrder(), (QStringList{
        QStringLiteral("Apple"), QStringLiteral("Mango"), QStringLiteral("Zebra")}));
}

QTEST_MAIN(TestSort)
#include "test_sort.moc"
