/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    CategoryRows / CategoryRowsModel — the By Category view's header and app
    rows, the flat-index and category lookups the view navigates with.
*/

#include "categoryrowsmodel.h"

#include <QSignalSpy>
#include <QTest>
#include <QVariantMap>

using CategoryRows::Kind;
using CategoryRows::Row;

namespace
{
QVariantMap app(const QString &id)
{
    return {{QStringLiteral("storageId"), id}};
}

// Sections "A" (5 apps), "B" (0 apps), "C" (2 apps).
QVariantList sampleSections()
{
    QVariantList a;
    for (int i = 0; i < 5; ++i) {
        a.append(app(QStringLiteral("a%1").arg(i)));
    }
    const QVariantList c{app(QStringLiteral("c0")), app(QStringLiteral("c1"))};
    return {
        QVariantMap{{QStringLiteral("category"), QStringLiteral("A")}, {QStringLiteral("apps"), a}},
        QVariantMap{{QStringLiteral("category"), QStringLiteral("B")}, {QStringLiteral("apps"), QVariantList()}},
        QVariantMap{{QStringLiteral("category"), QStringLiteral("C")}, {QStringLiteral("apps"), c}},
    };
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

    void modelExposesRows()
    {
        CategoryRowsModel model;
        model.setColumns(2);
        model.setGroupedApps(sampleSections());
        QCOMPARE(model.rowCount(), 7);

        const QModelIndex header = model.index(0, 0);
        QCOMPARE(header.data(CategoryRowsModel::KindRole).toString(), QStringLiteral("header"));
        QCOMPARE(header.data(CategoryRowsModel::CategoryRole).toString(), QStringLiteral("A"));

        const QModelIndex lastOfA = model.index(3, 0);
        QCOMPARE(lastOfA.data(CategoryRowsModel::KindRole).toString(), QStringLiteral("apps"));
        QCOMPARE(lastOfA.data(CategoryRowsModel::FirstIndexRole).toInt(), 4);
        QCOMPARE(idsOf(lastOfA.data(CategoryRowsModel::AppsRole).toList()), QStringList{QStringLiteral("a4")});

        const QModelIndex rowOfC = model.index(6, 0);
        QCOMPARE(rowOfC.data(CategoryRowsModel::SectionRole).toInt(), 2);
        QCOMPARE(idsOf(rowOfC.data(CategoryRowsModel::AppsRole).toList()), (QStringList{QStringLiteral("c0"), QStringLiteral("c1")}));
    }

    void columnsChangeRelayouts()
    {
        CategoryRowsModel model;
        model.setGroupedApps(sampleSections());
        QCOMPARE(model.rowCount(), 10); // 3 headers + 5 + 0 + 2 single-app rows

        QSignalSpy reset(&model, &QAbstractItemModel::modelReset);
        QSignalSpy changed(&model, &CategoryRowsModel::columnsChanged);
        model.setColumns(5);
        QCOMPARE(model.rowCount(), 5);
        QCOMPARE(reset.count(), 1);
        QCOMPARE(changed.count(), 1);

        model.setColumns(5);
        QCOMPARE(reset.count(), 1);
        QCOMPARE(changed.count(), 1);
    }

    void lookups()
    {
        CategoryRowsModel model;
        model.setColumns(2);
        model.setGroupedApps(sampleSections());

        QCOMPARE(model.rowForFlatIndex(0), 1);
        QCOMPARE(model.rowForFlatIndex(3), 2);
        QCOMPARE(model.rowForFlatIndex(4), 3);
        QCOMPARE(model.rowForFlatIndex(6), 6);
        QCOMPARE(model.rowForFlatIndex(7), -1);
        QCOMPARE(model.rowForFlatIndex(-1), -1);

        QCOMPARE(model.rowForCategory(QStringLiteral("A")), 0);
        QCOMPARE(model.rowForCategory(QStringLiteral("B")), 4);
        QCOMPARE(model.rowForCategory(QStringLiteral("C")), 5);
        QCOMPARE(model.rowForCategory(QStringLiteral("missing")), -1);
    }
};

QTEST_GUILESS_MAIN(TestCategoryRows)
#include "test_categoryrows.moc"
