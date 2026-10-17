/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    CategoryRows / CategoryRowsModel — the By Category view's header and app
    rows over a source app model, and the flat-index and category lookups the
    view navigates with.
*/

#include "categoryrowsmodel.h"
#include "stubappmodel.h"

#include <QSignalSpy>
#include <QTest>
#include <QVariantMap>

using CategoryRows::Kind;
using CategoryRows::Row;

namespace
{
StubApp app(const QString &id, const QStringList &categories)
{
    return {id, {}, {}, categories, {}, id, {}, {}, {}};
}

// Category "A" holds a0..a4, "C" holds c0 and c1.
QVector<StubApp> sampleApps()
{
    QVector<StubApp> apps;
    for (int i = 0; i < 5; ++i) {
        apps.append(app(QStringLiteral("a%1").arg(i), {QStringLiteral("A")}));
    }
    apps.append(app(QStringLiteral("c0"), {QStringLiteral("C")}));
    apps.append(app(QStringLiteral("c1"), {QStringLiteral("C")}));
    return apps;
}

QStringList idsOf(const QVariantList &apps)
{
    QStringList ids;
    for (const QVariant &entry : apps) {
        ids.append(entry.toMap().value(QStringLiteral("storageId")).toString());
    }
    return ids;
}
}

class TestCategoryRows : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void buildSplitsSectionsIntoRows()
    {
        const QList<Row> rows = CategoryRows::build({5, 0, 2}, 2);
        const QList<Row> expected{
            {Kind::Header, 0, 0, 0, 0},
            {Kind::Apps, 0, 0, 2, 0},
            {Kind::Apps, 0, 2, 2, 2},
            {Kind::Apps, 0, 4, 1, 4},
            {Kind::Header, 1, 0, 0, 5},
            {Kind::Header, 2, 0, 0, 5},
            {Kind::Apps, 2, 0, 2, 5},
        };
        QCOMPARE(rows, expected);
    }

    void buildClampsColumns()
    {
        QCOMPARE(CategoryRows::build({2}, 0), CategoryRows::build({2}, 1));
        QCOMPARE(CategoryRows::build({2}, 1).size(), 3);
        QVERIFY(CategoryRows::build({}, 4).isEmpty());
    }

    void inactiveModelIsEmpty()
    {
        StubAppModel source;
        source.setApps(sampleApps());
        CategoryRowsModel model;
        model.setSourceModel(&source);
        QCOMPARE(model.rowCount(), 0);
        QCOMPARE(model.appCount(), 0);

        model.setActive(true);
        QCOMPARE(model.rowCount(), 2 + 5 + 2); // grouped at once, not a turn later
        model.setActive(false);
        QCOMPARE(model.rowCount(), 0);
    }

    void modelExposesRows()
    {
        StubAppModel source;
        source.setApps(sampleApps());
        CategoryRowsModel model;
        model.setColumns(2);
        model.setSourceModel(&source);
        model.setActive(true);
        QCOMPARE(model.rowCount(), 6); // A: header + 3 rows, C: header + 1 row

        const QModelIndex header = model.index(0, 0);
        QCOMPARE(header.data(CategoryRowsModel::KindRole).toString(), QStringLiteral("header"));
        QCOMPARE(header.data(CategoryRowsModel::CategoryRole).toString(), QStringLiteral("A"));

        const QModelIndex lastOfA = model.index(3, 0);
        QCOMPARE(lastOfA.data(CategoryRowsModel::KindRole).toString(), QStringLiteral("apps"));
        QCOMPARE(lastOfA.data(CategoryRowsModel::FirstIndexRole).toInt(), 4);
        QCOMPARE(idsOf(lastOfA.data(CategoryRowsModel::AppsRole).toList()), QStringList{QStringLiteral("a4")});

        const QModelIndex rowOfC = model.index(5, 0);
        QCOMPARE(rowOfC.data(CategoryRowsModel::SectionRole).toInt(), 1);
        QCOMPARE(idsOf(rowOfC.data(CategoryRowsModel::AppsRole).toList()), (QStringList{QStringLiteral("c0"), QStringLiteral("c1")}));
    }

    void columnsChangeRelayouts()
    {
        StubAppModel source;
        source.setApps(sampleApps());
        CategoryRowsModel model;
        model.setSourceModel(&source);
        model.setActive(true);
        QCOMPARE(model.rowCount(), 9);

        QSignalSpy reset(&model, &QAbstractItemModel::modelReset);
        QSignalSpy columns(&model, &CategoryRowsModel::columnsChanged);
        QSignalSpy sections(&model, &CategoryRowsModel::sectionsChanged);
        model.setColumns(5);
        QCOMPARE(model.rowCount(), 4);
        QCOMPARE(reset.count(), 1);
        QCOMPARE(columns.count(), 1);
        QCOMPARE(sections.count(), 0); // same grouping, only new rows

        model.setColumns(5);
        QCOMPARE(reset.count(), 1);
    }

    void sourceChangeRegroupsOnce()
    {
        StubAppModel source;
        source.setApps(sampleApps());
        CategoryRowsModel model;
        model.setSourceModel(&source);
        model.setActive(true);

        QSignalSpy sections(&model, &CategoryRowsModel::sectionsChanged);
        source.setApps({app(QStringLiteral("b0"), {QStringLiteral("B")})});
        source.setApps({app(QStringLiteral("b0"), {QStringLiteral("B")}), app(QStringLiteral("b1"), {QStringLiteral("B")})});
        QCOMPARE(sections.count(), 0); // coalesced to the next turn
        QTRY_COMPARE(sections.count(), 1);
        QCOMPARE(model.appCount(), 2);
        QCOMPARE(model.storageIdAt(1), QStringLiteral("b1"));
    }

    void lookups()
    {
        StubAppModel source;
        source.setApps(sampleApps());
        CategoryRowsModel model;
        model.setColumns(2);
        model.setSourceModel(&source);
        model.setActive(true);

        QCOMPARE(model.appCount(), 7);
        QCOMPARE(model.storageIdAt(0), QStringLiteral("a0"));
        QCOMPARE(model.storageIdAt(5), QStringLiteral("c0"));
        QCOMPARE(model.storageIdAt(7), QString());
        QCOMPARE(model.proxyIndexAt(6), 6);
        QCOMPARE(model.proxyIndexAt(-1), -1);

        QCOMPARE(model.rowForFlatIndex(0), 1);
        QCOMPARE(model.rowForFlatIndex(3), 2);
        QCOMPARE(model.rowForFlatIndex(4), 3);
        QCOMPARE(model.rowForFlatIndex(6), 5);
        QCOMPARE(model.rowForFlatIndex(7), -1);

        QCOMPARE(model.rowForCategory(QStringLiteral("A")), 0);
        QCOMPARE(model.rowForCategory(QStringLiteral("C")), 4);
        QCOMPARE(model.rowForCategory(QStringLiteral("missing")), -1);
        QCOMPARE(model.flatIndexOfCategory(QStringLiteral("C")), 5);
        QCOMPARE(model.flatIndexOfCategory(QStringLiteral("missing")), -1);
    }
};

QTEST_GUILESS_MAIN(TestCategoryRows)
#include "test_categoryrows.moc"
