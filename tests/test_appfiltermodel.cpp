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
    void isNewAppReturnsFalseWhenKnownEmpty();
    void isNewAppReturnsTrueForUnknown();
    void getByStorageIdReturnsMatchingMap();
    void getByStorageIdReturnsEmptyWhenMissing();
    void getByStorageIdReturnsEmptyForEmptyId();
    void completionForCompletesNamePrefix();
    void completionForCompletesWordAcrossFields();
    void completionForEmptyQueryReturnsEmpty();
    void launchByStorageIdRecordsRecent();
    void launchByStorageIdIgnoresUnknownAndEmpty();
    void launchByProxyIndexRecordsRecent();
    void launchByProxyIndexIgnoresInvalidIndex();
    void getReturnsEmptyForInvalidRow();
    void nonEmptyCategoriesSkipsHiddenApps();
    void appsByCategoryGroupsMultiCategoryApp();
    void countSignalEmitsOnSourceChange();
    void markAllKnownPopulatesFromSource();
    void hideAppByProxyIndexAddsToList();
    void hideAppDoesNothingForInvalidIndex();
    void unhideAppRemovesFromList();
    void isRecentReflectsList();
    void setRecentAppsSkipsWorkWhenUnchanged();
    void hiddenAppsChangedTriggersGroupedSignal();
    void recordRecentLaunchPrependsAndBumpsCount();
    void recordRecentLaunchCapsAtMaxRecentApps();
    void recordRecentLaunchDeduplicatesPriorEntry();
    void recordRecentLaunchAddsToKnownApps();
    void recordRecentLaunchIgnoresEmptyId();
    void iconChangedBumpsIconGeneration();

private:
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
    m_filter.setKnownApps({});
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

void TestAppFilterModel::isNewAppReturnsFalseWhenKnownEmpty()
{
    QVERIFY(m_filter.knownApps().isEmpty());
    QVERIFY(!m_filter.isNewApp(QStringLiteral("anything")));
}

void TestAppFilterModel::isNewAppReturnsTrueForUnknown()
{
    m_filter.setKnownApps({QStringLiteral("a"), QStringLiteral("b")});
    QVERIFY(!m_filter.isNewApp(QStringLiteral("a")));
    QVERIFY(m_filter.isNewApp(QStringLiteral("c")));
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

// launch()/launchByStorageId run their recents bookkeeping before delegating
// the real KService launch to AppModel — so with a plain stub source the
// bookkeeping (sid resolution + recordRecentLaunch) is observable while the
// actual launch is a no-op (the qobject_cast<AppModel*> fails).

void TestAppFilterModel::launchByStorageIdRecordsRecent()
{
    m_filter.setMaxRecentApps(6);
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    m_filter.launchByStorageId(QStringLiteral("b"));
    QCOMPARE(m_filter.recentApps(), QStringList{QStringLiteral("b")});
}

void TestAppFilterModel::launchByStorageIdIgnoresUnknownAndEmpty()
{
    m_filter.setMaxRecentApps(6);
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
    });
    m_filter.launchByStorageId(QStringLiteral("nonexistent"));
    QVERIFY(m_filter.recentApps().isEmpty());
    m_filter.launchByStorageId(QString());
    QVERIFY(m_filter.recentApps().isEmpty());
}

void TestAppFilterModel::launchByProxyIndexRecordsRecent()
{
    m_filter.setMaxRecentApps(6);
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    // Alphabetical → proxy row 0 is "A" (storageId "a").
    m_filter.launch(0);
    QCOMPARE(m_filter.recentApps(), QStringList{QStringLiteral("a")});
}

void TestAppFilterModel::launchByProxyIndexIgnoresInvalidIndex()
{
    m_filter.setMaxRecentApps(6);
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
    });
    m_filter.launch(99);
    QVERIFY(m_filter.recentApps().isEmpty());
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
    const auto groups = m_filter.appsByCategory();
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

void TestAppFilterModel::markAllKnownPopulatesFromSource()
{
    m_source.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {}, {}, QStringLiteral("c"), {}, {}, {}},
    });
    QVERIFY(m_filter.knownApps().isEmpty());
    m_filter.markAllKnown();
    QStringList known = m_filter.knownApps();
    known.sort();
    QCOMPARE(known, (QStringList{QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("c")}));
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

void TestAppFilterModel::hiddenAppsChangedTriggersGroupedSignal()
{
    QSignalSpy spy(&m_filter, &AppFilterModel::groupedByCategoryChanged);
    m_filter.setHiddenApps({QStringLiteral("a")});
    // Exactly once: the markGroupedDirty lambda coalesces to a single emit.
    QCOMPARE(spy.count(), 1);
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

void TestAppFilterModel::recordRecentLaunchAddsToKnownApps()
{
    QVERIFY(m_filter.knownApps().isEmpty());
    m_filter.recordRecentLaunch(QStringLiteral("newapp"));
    QVERIFY(m_filter.knownApps().contains(QStringLiteral("newapp")));
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

QTEST_MAIN(TestAppFilterModel)
#include "test_appfiltermodel.moc"
