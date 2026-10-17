/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Smoke tests for AppFilterModel: property accessors, signal emission,
    round-trip of list-typed properties.
*/

#include <KIconLoader>

#include <QSignalSpy>
#include <QTest>

#include "appfiltermodel.h"
#include "categoryqueries.h"
#include "stubappmodel.h"

class TestAppFilterModel : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void searchTextEmitsSignalOnceOnChange();
    void sortModeChangeEmitsSignal();
    void favoritesToggleRoundtrip();
    void hiddenAppsRoundtrip();
    void launchCountsMapRoundtrip();
    void maxRecentAppsSetterEmitsSignal();
    void getByStorageIdReturnsMatchingMap();
    void getByStorageIdReturnsEmptyWhenMissing();
    void getByStorageIdReturnsEmptyForEmptyId();
    void completionForCompletesNamePrefix();
    void completionForCompletesWordAcrossFields();
    void completionForEmptyQueryReturnsEmpty();
    void getReturnsEmptyForInvalidRow();
    void nonEmptyCategoriesSkipsHiddenApps();
    void appsByCategoryGroupsMultiCategoryApp();
    void countSignalEmitsOnSourceChange();
    void hideAppByProxyIndexAddsToList();
    void hideAppDoesNothingForInvalidIndex();
    void searchStateIsOnePass();
    void benchmarkSearchStartAndEnd_data();
    void benchmarkSearchStartAndEnd();
    void unhideAppRemovesFromList();
    void isRecentReflectsList();
    void setRecentAppsSkipsWorkWhenUnchanged();
    void recordRecentLaunchPrependsAndBumpsCount();
    void recordRecentLaunchCapsAtMaxRecentApps();
    void recordRecentLaunchDeduplicatesPriorEntry();
    void recordRecentLaunchIgnoresEmptyId();
    void iconChangedBumpsIconGeneration();
    void databaseReloadPrunesUninstalledRecents();

private:
    // ~300 apps over a few categories, every 10th a favourite: enough rows
    // for a search transition to cost something measurable.
    void fillManyApps();
    // Structural change notifications the views rebuild on.
    struct PassSpies {
        explicit PassSpies(AppFilterModel *m)
            : layout(m, &QAbstractItemModel::layoutChanged)
            , inserted(m, &QAbstractItemModel::rowsInserted)
            , removed(m, &QAbstractItemModel::rowsRemoved)
            , reset(m, &QAbstractItemModel::modelReset)
        {
        }
        int count() const
        {
            return layout.count() + inserted.count() + removed.count() + reset.count();
        }
        QSignalSpy layout;
        QSignalSpy inserted;
        QSignalSpy removed;
        QSignalSpy reset;
    };
    // A search transition the way SearchSessionManager drives it today.
    void startSearchSeparately()
    {
        m_filter.setFilterCategory(QString());
        m_filter.setShowFavoritesOnly(false);
        m_filter.setSearchText(QStringLiteral("app 1"));
    }
    void endSearchSeparately()
    {
        m_filter.setFilterCategory(QStringLiteral("Cat0"));
        m_filter.setShowFavoritesOnly(true);
        m_filter.setSearchText(QString());
    }

    StubAppModel m_source;
    AppFilterModel m_filter;
};

void TestAppFilterModel::initTestCase()
{
    m_filter.setSourceModel(&m_source);
}

void TestAppFilterModel::init()
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
}

void TestAppFilterModel::searchTextEmitsSignalOnceOnChange()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::searchTextChanged);
    m_filter.setSearchText(QStringLiteral("firefox"));
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.searchText(), QStringLiteral("firefox"));

    m_filter.setSearchText(QStringLiteral("firefox"));
    QCOMPARE(spy.count(), 1); // no signal when unchanged
}

void TestAppFilterModel::sortModeChangeEmitsSignal()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::sortModeChanged);
    m_filter.setSortMode(AppFilterModel::MostUsed);
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.sortMode(), int(AppFilterModel::MostUsed));

    m_filter.setSortMode(AppFilterModel::ByCategory);
    QCOMPARE(spy.count(), 2);
}

void TestAppFilterModel::favoritesToggleRoundtrip()
{
    const QString id = QStringLiteral("test.desktop");
    QVERIFY(!m_filter.isFavorite(id));
    m_filter.setFavoriteApps({id});
    QVERIFY(m_filter.isFavorite(id));
    QCOMPARE(m_filter.favoriteApps(), QStringList{id});
}

void TestAppFilterModel::hiddenAppsRoundtrip()
{
    const QStringList ids = {QStringLiteral("a.desktop"), QStringLiteral("b.desktop")};
    QSignalSpy spy(&m_filter, &AppFilterModel::hiddenAppsChanged);
    m_filter.setHiddenApps(ids);
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.hiddenApps(), ids);
}

void TestAppFilterModel::launchCountsMapRoundtrip()
{
    QVariantMap in;
    in[QStringLiteral("a")] = 5;
    in[QStringLiteral("b")] = 12;
    m_filter.setLaunchCountsMap(in);
    QCOMPARE(m_filter.getLaunchCount(QStringLiteral("a")), 5);
    QCOMPARE(m_filter.getLaunchCount(QStringLiteral("b")), 12);
    QCOMPARE(m_filter.getLaunchCount(QStringLiteral("missing")), 0);
}

void TestAppFilterModel::maxRecentAppsSetterEmitsSignal()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::maxRecentAppsChanged);
    m_filter.setMaxRecentApps(10);
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.maxRecentApps(), 10);
    m_filter.setMaxRecentApps(10);
    QCOMPARE(spy.count(), 1); // no signal when unchanged
}

void TestAppFilterModel::getByStorageIdReturnsMatchingMap()
{
    m_source.setApps({
        {QStringLiteral("Kate"),
         QStringLiteral("kate-icon"),
         QStringLiteral("/x/kate.desktop"),
         {QStringLiteral("Development")},
         QStringLiteral("Editor"),
         QStringLiteral("kate"),
         {},
         QStringLiteral("Text editor"),
         QStringLiteral("System")},
    });
    const auto map = m_filter.getByStorageId(QStringLiteral("kate"));
    QCOMPARE(map.value(QStringLiteral("name")).toString(), QStringLiteral("Kate"));
    QCOMPARE(map.value(QStringLiteral("iconName")).toString(), QStringLiteral("kate-icon"));
    QCOMPARE(map.value(QStringLiteral("storageId")).toString(), QStringLiteral("kate"));
}

void TestAppFilterModel::getByStorageIdReturnsEmptyWhenMissing()
{
    m_source.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    QVERIFY(m_filter.getByStorageId(QStringLiteral("ghost")).isEmpty());
}

void TestAppFilterModel::getByStorageIdReturnsEmptyForEmptyId()
{
    m_source.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    QVERIFY(m_filter.getByStorageId(QString()).isEmpty());
}

void TestAppFilterModel::completionForCompletesNamePrefix()
{
    m_source.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    // Name starts with the query → complete the whole name.
    QCOMPARE(m_filter.completionFor(QStringLiteral("ka")), QStringLiteral("Kate"));
}

void TestAppFilterModel::completionForCompletesWordAcrossFields()
{
    m_source.setApps({
        {QStringLiteral("Ghostty"), {}, {}, {}, QStringLiteral("Terminal emulator"), QStringLiteral("ghostty"), {}, {}, {}},
    });
    // No name prefix; pass 2 completes a word from the generic name.
    QCOMPARE(m_filter.completionFor(QStringLiteral("te")), QStringLiteral("Terminal"));
}

void TestAppFilterModel::completionForEmptyQueryReturnsEmpty()
{
    m_source.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    QVERIFY(m_filter.completionFor(QString()).isEmpty());
}

void TestAppFilterModel::getReturnsEmptyForInvalidRow()
{
    QVERIFY(m_filter.get(-1).isEmpty());
    QVERIFY(m_filter.get(9999).isEmpty());
}

void TestAppFilterModel::nonEmptyCategoriesSkipsHiddenApps()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {QStringLiteral("X")}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {QStringLiteral("Y")}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    QStringList cats = m_filter.nonEmptyCategories();
    cats.sort();
    QCOMPARE(cats, (QStringList{QStringLiteral("X"), QStringLiteral("Y")}));

    m_filter.setHiddenApps({QStringLiteral("b")});
    cats = m_filter.nonEmptyCategories();
    cats.sort();
    QCOMPARE(cats, QStringList{QStringLiteral("X")});
}

void TestAppFilterModel::appsByCategoryGroupsMultiCategoryApp()
{
    m_source.setApps({
        {QStringLiteral("Multi"), {}, {}, {QStringLiteral("Dev"), QStringLiteral("Util")}, {}, QStringLiteral("m"), {}, {}, {}},
        {QStringLiteral("Single"), {}, {}, {QStringLiteral("Dev")}, {}, QStringLiteral("s"), {}, {}, {}},
    });
    const auto groups = CategoryQueries::groupByCategory(&m_filter);
    QCOMPARE(groups.size(), 2);

    QHash<QString, int> appsPerCategory;
    for (const auto &g : groups) {
        const auto map = g.toMap();
        appsPerCategory[map.value(QStringLiteral("category")).toString()] = map.value(QStringLiteral("apps")).toList().size();
    }
    QCOMPARE(appsPerCategory.value(QStringLiteral("Dev")), 2);
    QCOMPARE(appsPerCategory.value(QStringLiteral("Util")), 1);
}

void TestAppFilterModel::countSignalEmitsOnSourceChange()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::countChanged);
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
    });
    // Exactly once: the ctor de-duplicates countChanged to one emit per reset.
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.count(), 1);
}

void TestAppFilterModel::hideAppByProxyIndexAddsToList()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    QSignalSpy spy(&m_filter, &AppFilterModel::hiddenAppsChanged);
    // Alphabetical sort → proxy row 0 is "A" (storageId "a").
    m_filter.hideApp(0);
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.hiddenApps(), QStringList{QStringLiteral("a")});
    // "a" is now filtered out of the normal view, so row 0 becomes "B".
    // Hiding row 0 again hides "b" — the row shifted; it is not a re-hide.
    QCOMPARE(m_filter.count(), 1);
    m_filter.hideApp(0);
    QCOMPARE(spy.count(), 2);
    const auto hidden = m_filter.hiddenApps();
    QVERIFY(hidden.contains(QStringLiteral("a")));
    QVERIFY(hidden.contains(QStringLiteral("b")));
}

void TestAppFilterModel::hideAppDoesNothingForInvalidIndex()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::hiddenAppsChanged);
    m_filter.hideApp(99);
    QCOMPARE(spy.count(), 0);
    QVERIFY(m_filter.hiddenApps().isEmpty());
}

void TestAppFilterModel::unhideAppRemovesFromList()
{
    m_filter.setHiddenApps({QStringLiteral("a"), QStringLiteral("b")});
    QSignalSpy spy(&m_filter, &AppFilterModel::hiddenAppsChanged);
    m_filter.unhideApp(QStringLiteral("a"));
    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.hiddenApps(), QStringList{QStringLiteral("b")});

    // Unknown id is no-op
    m_filter.unhideApp(QStringLiteral("ghost"));
    QCOMPARE(spy.count(), 1);
}

void TestAppFilterModel::isRecentReflectsList()
{
    QVERIFY(!m_filter.isRecent(QStringLiteral("x")));
    m_filter.setRecentApps({QStringLiteral("x"), QStringLiteral("y")});
    QVERIFY(m_filter.isRecent(QStringLiteral("x")));
    QVERIFY(!m_filter.isRecent(QStringLiteral("z")));
}

void TestAppFilterModel::setRecentAppsSkipsWorkWhenUnchanged()
{
    const QStringList list{QStringLiteral("a"), QStringLiteral("b")};
    m_filter.setRecentApps(list);

    QSignalSpy changed(&m_filter, &AppFilterModel::recentAppsChanged);
    QSignalSpy layout(&m_filter, &AppFilterModel::layoutChanged);

    m_filter.setRecentApps(list);
    QCOMPARE(changed.count(), 0);
    QCOMPARE(layout.count(), 0);

    m_filter.setRecentApps({QStringLiteral("c")});
    QCOMPARE(changed.count(), 1);
}

void TestAppFilterModel::recordRecentLaunchPrependsAndBumpsCount()
{
    QSignalSpy recentSpy(&m_filter, &AppFilterModel::recentAppsChanged);
    QSignalSpy countSpy(&m_filter, &AppFilterModel::launchCountsChanged);

    m_filter.recordRecentLaunch(QStringLiteral("a"));
    QCOMPARE(m_filter.recentApps().first(), QStringLiteral("a"));
    QCOMPARE(m_filter.getLaunchCount(QStringLiteral("a")), 1);
    QCOMPARE(recentSpy.count(), 1);
    QCOMPARE(countSpy.count(), 1);

    m_filter.recordRecentLaunch(QStringLiteral("a"));
    QCOMPARE(m_filter.getLaunchCount(QStringLiteral("a")), 2);
}

void TestAppFilterModel::recordRecentLaunchCapsAtMaxRecentApps()
{
    m_filter.setMaxRecentApps(3);
    m_filter.recordRecentLaunch(QStringLiteral("a"));
    m_filter.recordRecentLaunch(QStringLiteral("b"));
    m_filter.recordRecentLaunch(QStringLiteral("c"));
    m_filter.recordRecentLaunch(QStringLiteral("d"));
    QCOMPARE(m_filter.recentApps().size(), 3);
    QCOMPARE(m_filter.recentApps(), (QStringList{QStringLiteral("d"), QStringLiteral("c"), QStringLiteral("b")}));
}

void TestAppFilterModel::recordRecentLaunchDeduplicatesPriorEntry()
{
    m_filter.recordRecentLaunch(QStringLiteral("a"));
    m_filter.recordRecentLaunch(QStringLiteral("b"));
    m_filter.recordRecentLaunch(QStringLiteral("a")); // bump to front
    QCOMPARE(m_filter.recentApps(), (QStringList{QStringLiteral("a"), QStringLiteral("b")}));
}

void TestAppFilterModel::recordRecentLaunchIgnoresEmptyId()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::recentAppsChanged);
    m_filter.recordRecentLaunch(QString());
    QCOMPARE(spy.count(), 0);
    QVERIFY(m_filter.recentApps().isEmpty());
}

void TestAppFilterModel::iconChangedBumpsIconGeneration()
{
    // System icon-theme switch / icon-file replacement (#86, #103) arrives as
    // KIconLoader::iconChanged. iconGeneration must increment so QML icons can
    // force an in-place reload (the icon name is unchanged, so Kirigami.Icon
    // would not re-resolve on its own).
    const int before = m_filter.iconGeneration();
    QSignalSpy spy(&m_filter, &AppFilterModel::iconGenerationChanged);
    QVERIFY(spy.isValid());

    QMetaObject::invokeMethod(KIconLoader::global(), "iconChanged", Qt::DirectConnection, Q_ARG(int, int(KIconLoader::NoGroup)));

    QCOMPARE(spy.count(), 1);
    QVERIFY(m_filter.iconGeneration() > before);
}

void TestAppFilterModel::databaseReloadPrunesUninstalledRecents()
{
    // Two apps installed, both recent. After one is uninstalled (the source
    // model resets to just the survivor), the recents list must drop the gone
    // app and emit recentAppsChanged so the persisted store follows (#).
    m_source.setApps({
        {QStringLiteral("Keep"), {}, QStringLiteral("/x/keep.desktop"), {}, {}, QStringLiteral("keep.desktop"), {}, {}, {}},
        {QStringLiteral("Gone"), {}, QStringLiteral("/x/gone.desktop"), {}, {}, QStringLiteral("gone.desktop"), {}, {}, {}},
    });
    m_filter.setRecentApps({QStringLiteral("gone.desktop"), QStringLiteral("keep.desktop")});

    QSignalSpy spy(&m_filter, &AppFilterModel::recentAppsChanged);
    // Uninstall "gone": the source reloads with only the survivor.
    m_source.setApps({
        {QStringLiteral("Keep"), {}, QStringLiteral("/x/keep.desktop"), {}, {}, QStringLiteral("keep.desktop"), {}, {}, {}},
    });

    QCOMPARE(spy.count(), 1);
    QCOMPARE(m_filter.recentApps(), QStringList{QStringLiteral("keep.desktop")});
}

void TestAppFilterModel::fillManyApps()
{
    QVector<StubApp> apps;
    QStringList favorites;
    for (int i = 0; i < 300; ++i) {
        const QString id = QStringLiteral("app%1.desktop").arg(i);
        apps.append({QStringLiteral("App %1").arg(i),
                     QStringLiteral("icon"),
                     QStringLiteral("/x/") + id,
                     {QStringLiteral("Cat%1").arg(i % 5)},
                     QStringLiteral("Generic %1").arg(i),
                     id,
                     {},
                     QStringLiteral("Comment %1").arg(i),
                     QString()});
        if (i % 10 == 0) {
            favorites.append(id);
        }
    }
    m_source.setApps(apps);
    m_filter.setFavoriteApps(favorites);
}

// setSearchState() makes a search start and end one proxy pass each — one
// structural notification for the view — with the same rows as the separate
// setters.
void TestAppFilterModel::searchStateIsOnePass()
{
    fillManyApps();
    m_filter.setSearchState(QString(), QStringLiteral("Cat0"), true);
    const int browsingRows = m_filter.rowCount();
    QCOMPARE(browsingRows, 30);

    QSignalSpy textSpy(&m_filter, &AppFilterModel::searchTextChanged);
    QSignalSpy categorySpy(&m_filter, &AppFilterModel::filterCategoryChanged);
    QSignalSpy favoritesSpy(&m_filter, &AppFilterModel::showFavoritesOnlyChanged);

    PassSpies start(&m_filter);
    m_filter.setSearchState(QStringLiteral("app 1"), QString(), false);
    QCOMPARE(start.count(), 1);
    const int searchRows = m_filter.rowCount();
    QCOMPARE(m_filter.searchText(), QStringLiteral("app 1"));
    QCOMPARE(m_filter.filterCategory(), QString());
    QVERIFY(!m_filter.showFavoritesOnly());
    QCOMPARE(textSpy.count(), 1);
    QCOMPARE(categorySpy.count(), 1);
    QCOMPARE(favoritesSpy.count(), 1);

    PassSpies end(&m_filter);
    m_filter.setSearchState(QString(), QStringLiteral("Cat0"), true);
    QCOMPARE(end.count(), 1);
    QCOMPARE(m_filter.rowCount(), browsingRows);

    // Same rows as setting the three properties one by one.
    startSearchSeparately();
    QCOMPARE(m_filter.rowCount(), searchRows);

    // Unchanged state: no pass, no notification.
    PassSpies none(&m_filter);
    m_filter.setSearchState(QStringLiteral("app 1"), QString(), false);
    QCOMPARE(none.count(), 0);
}

void TestAppFilterModel::benchmarkSearchStartAndEnd_data()
{
    QTest::addColumn<bool>("batched");
    QTest::newRow("separate setters") << false;
    QTest::newRow("setSearchState") << true;
}

void TestAppFilterModel::benchmarkSearchStartAndEnd()
{
    QFETCH(bool, batched);
    fillManyApps();
    m_filter.setFilterCategory(QStringLiteral("Cat0"));
    m_filter.setShowFavoritesOnly(true);
    // The proxy maps rows lazily: read them back after each transition, as a
    // bound view does, or the benchmark measures nothing.
    QBENCHMARK {
        if (batched) {
            m_filter.setSearchState(QStringLiteral("app 1"), QString(), false);
        } else {
            startSearchSeparately();
        }
        QVERIFY(m_filter.rowCount() > 0);
        if (batched) {
            m_filter.setSearchState(QString(), QStringLiteral("Cat0"), true);
        } else {
            endSearchSeparately();
        }
        QVERIFY(m_filter.rowCount() > 0);
    }
}

QTEST_MAIN(TestAppFilterModel)
#include "test_appfiltermodel.moc"
