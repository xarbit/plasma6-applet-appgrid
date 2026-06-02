/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Verifies filterAcceptsRow logic: category, hidden, favorites-only,
    and recents-from-grid hiding.
*/

#include <QTest>

#include "appfiltermodel.h"
#include "stubappmodel.h"

class TestFilter : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void initTestCase();
    void init();
    void hiddenAppsExcluded();
    void hiddenAppsStayHiddenInSearchByDefault();
    void hiddenAppsSurfaceInSearchWhenToggleOn();
    void categoryFilterIncludesOnlyMatching();
    void emptyCategoryAcceptsAll();
    void favoritesOnlyExcludesNonFavorites();
    void recentsHiddenFromAllViewInAlphabetical();
    void recentsVisibleInMostUsed();

private:
    QStringList visibleStorageIds() const;
    StubAppModel m_source;
    AppFilterModel m_filter;
};

void TestFilter::initTestCase()
{
    m_filter.setSourceModel(&m_source);
}

void TestFilter::init()
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
    m_filter.setSearchShowsHidden(false);
}

QStringList TestFilter::visibleStorageIds() const
{
    QStringList ids;
    for (int i = 0; i < m_filter.count(); ++i)
        ids << m_filter.index(i, 0).data(AppModel::StorageIdRole).toString();
    ids.sort();
    return ids;
}

void TestFilter::hiddenAppsExcluded()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a.desktop"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b.desktop"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c.desktop"), {}, {}, {}},
    });
    m_filter.setHiddenApps({QStringLiteral("b.desktop")});
    QCOMPARE(visibleStorageIds(), (QStringList{QStringLiteral("a.desktop"), QStringLiteral("c.desktop")}));
}

void TestFilter::hiddenAppsStayHiddenInSearchByDefault()
{
    m_source.setApps({
        {QStringLiteral("Konsole"), {}, {}, {}, {}, QStringLiteral("konsole.desktop"), {}, {}, {}},
        {QStringLiteral("Krita"),   {}, {}, {}, {}, QStringLiteral("krita.desktop"),   {}, {}, {}},
    });
    m_filter.setHiddenApps({QStringLiteral("krita.desktop")});
    // Empty query → hidden app excluded from the grid (existing).
    QCOMPARE(visibleStorageIds(), QStringList{QStringLiteral("konsole.desktop")});
    // Search → hidden app still excluded (searchShowsHidden defaults false).
    m_filter.setSearchText(QStringLiteral("kri"));
    QCOMPARE(visibleStorageIds(), QStringList());
}

void TestFilter::hiddenAppsSurfaceInSearchWhenToggleOn()
{
    m_source.setApps({
        {QStringLiteral("Konsole"), {}, {}, {}, {}, QStringLiteral("konsole.desktop"), {}, {}, {}},
        {QStringLiteral("Krita"),   {}, {}, {}, {}, QStringLiteral("krita.desktop"),   {}, {}, {}},
    });
    m_filter.setHiddenApps({QStringLiteral("krita.desktop")});
    m_filter.setSearchShowsHidden(true);
    m_filter.setSearchText(QStringLiteral("kri"));
    QCOMPARE(visibleStorageIds(), QStringList{QStringLiteral("krita.desktop")});
}

void TestFilter::categoryFilterIncludesOnlyMatching()
{
    m_source.setApps({
        {QStringLiteral("Kate"), {}, {}, {QStringLiteral("Development")}, {}, QStringLiteral("kate"), {}, {}, {}},
        {QStringLiteral("Firefox"), {}, {}, {QStringLiteral("Internet")}, {}, QStringLiteral("ff"), {}, {}, {}},
        {QStringLiteral("Code"), {}, {}, {QStringLiteral("Development"), QStringLiteral("Utility")}, {}, QStringLiteral("vs"), {}, {}, {}},
    });
    m_filter.setFilterCategory(QStringLiteral("Development"));
    QCOMPARE(visibleStorageIds(), (QStringList{QStringLiteral("kate"), QStringLiteral("vs")}));
    m_filter.setFilterCategory(QStringLiteral("Internet"));
    QCOMPARE(visibleStorageIds(), QStringList{QStringLiteral("ff")});
}

void TestFilter::emptyCategoryAcceptsAll()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {QStringLiteral("X")}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {QStringLiteral("Y")}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    m_filter.setFilterCategory(QString());
    QCOMPARE(m_filter.count(), 2);
}

void TestFilter::favoritesOnlyExcludesNonFavorites()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setFavoriteApps({QStringLiteral("c"), QStringLiteral("a")});
    m_filter.setShowFavoritesOnly(true);
    QCOMPARE(visibleStorageIds(), (QStringList{QStringLiteral("a"), QStringLiteral("c")}));
}

void TestFilter::recentsHiddenFromAllViewInAlphabetical()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    m_filter.setSortMode(AppFilterModel::Alphabetical);
    m_filter.setRecentApps({QStringLiteral("b")});
    QCOMPARE(visibleStorageIds(), (QStringList{QStringLiteral("a"), QStringLiteral("c")}));
}

void TestFilter::recentsVisibleInMostUsed()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    m_filter.setSortMode(AppFilterModel::MostUsed);
    m_filter.setRecentApps({QStringLiteral("b")});
    QCOMPARE(m_filter.count(), 2); // recents NOT filtered when sortMode != Alphabetical
}

QTEST_MAIN(TestFilter)
#include "test_filter.moc"
