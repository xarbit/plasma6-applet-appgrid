/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for CategoryQueries: the pure category grouping extracted from
    AppFilterModel, exercised against a stub source model.
*/

#include <QTest>

#include "categoryqueries.h"
#include "stubappmodel.h"

class TestCategoryQueries : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void appDataMapExposesSharedFields();
    void groupByCategorySectionsSortedWithProxyIndex();
    void groupByCategoryNullModelIsEmpty();
    void nonEmptyCategoriesSkipHiddenApps();
};

void TestCategoryQueries::appDataMapExposesSharedFields()
{
    StubAppModel model;
    model.setApps({
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
    const QVariantMap map = CategoryQueries::appDataMap(model.index(0, 0));
    QCOMPARE(map.value(QStringLiteral("name")).toString(), QStringLiteral("Kate"));
    QCOMPARE(map.value(QStringLiteral("iconName")).toString(), QStringLiteral("kate-icon"));
    QCOMPARE(map.value(QStringLiteral("desktopFile")).toString(), QStringLiteral("/x/kate.desktop"));
    QCOMPARE(map.value(QStringLiteral("storageId")).toString(), QStringLiteral("kate"));
    QCOMPARE(map.value(QStringLiteral("comment")).toString(), QStringLiteral("Text editor"));
    QCOMPARE(map.value(QStringLiteral("installSource")).toString(), QStringLiteral("System"));
    // genericName is a caller-added extra, not part of the shared map.
    QVERIFY(!map.contains(QStringLiteral("genericName")));
}

void TestCategoryQueries::groupByCategorySectionsSortedWithProxyIndex()
{
    StubAppModel model;
    model.setApps({
        {QStringLiteral("A"), {}, {}, {QStringLiteral("Development")}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {QStringLiteral("Development"), QStringLiteral("Network")}, {}, QStringLiteral("b"), {}, {}, {}},
        {QStringLiteral("C"), {}, {}, {QStringLiteral("Network")}, {}, QStringLiteral("c"), {}, {}, {}},
    });

    const QVariantList sections = CategoryQueries::groupByCategory(&model);
    QCOMPARE(sections.size(), 2);
    // QMap keeps sections alphabetical: Development before Network.
    QCOMPARE(sections.at(0).toMap().value(QStringLiteral("category")).toString(), QStringLiteral("Development"));
    QCOMPARE(sections.at(1).toMap().value(QStringLiteral("category")).toString(), QStringLiteral("Network"));

    const QVariantList devApps = sections.at(0).toMap().value(QStringLiteral("apps")).toList();
    QCOMPARE(devApps.size(), 2); // A and B
    QCOMPARE(devApps.at(0).toMap().value(QStringLiteral("storageId")).toString(), QStringLiteral("a"));
    QCOMPARE(devApps.at(0).toMap().value(QStringLiteral("proxyIndex")).toInt(), 0);
    QCOMPARE(devApps.at(1).toMap().value(QStringLiteral("proxyIndex")).toInt(), 1);

    const QVariantList netApps = sections.at(1).toMap().value(QStringLiteral("apps")).toList();
    QCOMPARE(netApps.size(), 2); // B (multi-category) and C
}

void TestCategoryQueries::nonEmptyCategoriesSkipHiddenApps()
{
    StubAppModel model;
    model.setApps({
        {QStringLiteral("A"), {}, {}, {QStringLiteral("X"), QStringLiteral("Y")}, {}, QStringLiteral("a"), {}, {}, {}},
        {QStringLiteral("B"), {}, {}, {QStringLiteral("Z")}, {}, QStringLiteral("b"), {}, {}, {}},
    });
    QStringList categories = CategoryQueries::nonEmptyCategories(&model, [](const QString &sid) {
        return sid == QLatin1String("b");
    });
    categories.sort();
    QCOMPARE(categories, QStringList({QStringLiteral("X"), QStringLiteral("Y")}));
    QVERIFY(CategoryQueries::nonEmptyCategories(nullptr, [](const QString &) {
                return false;
            }).isEmpty());
}

void TestCategoryQueries::groupByCategoryNullModelIsEmpty()
{
    QVERIFY(CategoryQueries::groupByCategory(nullptr).isEmpty());
}

QTEST_GUILESS_MAIN(TestCategoryQueries)
#include "test_categoryqueries.moc"
