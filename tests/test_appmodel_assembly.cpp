/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for AppModelAssembly::assemble — the dedup / category-merge /
    collation-sort extracted from AppModel::loadApplications so it can be tested
    without KService. Pins the behaviour the live model relies on.
*/

#include <QTest>

#include "appmodelassembly.h"

namespace
{
AppEntry occ(const QString &name, const QString &storageId, const QStringList &categories = {})
{
    AppEntry e;
    e.name = name;
    e.storageId = storageId;
    e.categories = categories;
    return e;
}

QStringList names(const QVector<AppEntry> &apps)
{
    QStringList out;
    for (const auto &a : apps) {
        out << a.name;
    }
    return out;
}
}

class TestAppModelAssembly : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void sortsCaseInsensitiveByName();
    void firstOccurrenceWinsFields();
    void simpleModeDropsDuplicateWithoutMerging();
    void systemModeMergesCategoriesOfDuplicates();
    void collectsSortedUniqueCategories();
    void skipsEmptyStorageId();
    void emptyNameClaimsIdAndSuppressesLaterDuplicate();
};

void TestAppModelAssembly::sortsCaseInsensitiveByName()
{
    const auto r = AppModelAssembly::assemble({
        occ(QStringLiteral("banana"), QStringLiteral("b")),
        occ(QStringLiteral("Apple"), QStringLiteral("a")),
        occ(QStringLiteral("cherry"), QStringLiteral("c")),
    }, /*systemMode=*/false);
    QCOMPARE(names(r.apps), (QStringList{QStringLiteral("Apple"), QStringLiteral("banana"), QStringLiteral("cherry")}));
}

void TestAppModelAssembly::firstOccurrenceWinsFields()
{
    AppEntry first;
    first.name = QStringLiteral("Kate");
    first.storageId = QStringLiteral("kate");
    first.icon = QStringLiteral("kate-icon");
    AppEntry dup;
    dup.name = QStringLiteral("Kate (dup)");
    dup.storageId = QStringLiteral("kate");
    dup.icon = QStringLiteral("other-icon");

    const auto r = AppModelAssembly::assemble({first, dup}, false);
    QCOMPARE(r.apps.size(), 1);
    QCOMPARE(r.apps.first().name, QStringLiteral("Kate"));
    QCOMPARE(r.apps.first().icon, QStringLiteral("kate-icon"));
}

void TestAppModelAssembly::simpleModeDropsDuplicateWithoutMerging()
{
    // Simple mode: the first occurrence already carries the full category set,
    // so a repeat is dropped and its categories are NOT merged.
    const auto r = AppModelAssembly::assemble({
        occ(QStringLiteral("Kate"), QStringLiteral("kate"), {QStringLiteral("Development")}),
        occ(QStringLiteral("Kate"), QStringLiteral("kate"), {QStringLiteral("Utilities")}),
    }, false);
    QCOMPARE(r.apps.size(), 1);
    QCOMPARE(r.apps.first().categories, QStringList{QStringLiteral("Development")});
}

void TestAppModelAssembly::systemModeMergesCategoriesOfDuplicates()
{
    // System mode: an app reachable from several menu groups accumulates each
    // group's category onto the single entry.
    const auto r = AppModelAssembly::assemble({
        occ(QStringLiteral("Kate"), QStringLiteral("kate"), {QStringLiteral("Development")}),
        occ(QStringLiteral("Kate"), QStringLiteral("kate"), {QStringLiteral("Utilities")}),
        occ(QStringLiteral("Kate"), QStringLiteral("kate"), {QStringLiteral("Development")}), // already present
    }, /*systemMode=*/true);
    QCOMPARE(r.apps.size(), 1);
    QCOMPARE(r.apps.first().categories,
             (QStringList{QStringLiteral("Development"), QStringLiteral("Utilities")}));
}

void TestAppModelAssembly::collectsSortedUniqueCategories()
{
    const auto r = AppModelAssembly::assemble({
        occ(QStringLiteral("A"), QStringLiteral("a"), {QStringLiteral("Internet"), QStringLiteral("Games")}),
        occ(QStringLiteral("B"), QStringLiteral("b"), {QStringLiteral("Games")}),
    }, false);
    QCOMPARE(r.categories, (QStringList{QStringLiteral("Games"), QStringLiteral("Internet")}));
}

void TestAppModelAssembly::skipsEmptyStorageId()
{
    const auto r = AppModelAssembly::assemble({
        occ(QStringLiteral("NoId"), QString()),
        occ(QStringLiteral("Real"), QStringLiteral("real")),
    }, false);
    QCOMPARE(r.apps.size(), 1);
    QCOMPARE(r.apps.first().name, QStringLiteral("Real"));
}

void TestAppModelAssembly::emptyNameClaimsIdAndSuppressesLaterDuplicate()
{
    // An empty-name occurrence marks the id seen (mirrors the original walk),
    // so a later named occurrence of the same id is suppressed.
    const auto r = AppModelAssembly::assemble({
        occ(QString(), QStringLiteral("ghost")),
        occ(QStringLiteral("Ghost"), QStringLiteral("ghost")),
    }, false);
    QVERIFY(r.apps.isEmpty());
}

QTEST_GUILESS_MAIN(TestAppModelAssembly)
#include "test_appmodel_assembly.moc"
