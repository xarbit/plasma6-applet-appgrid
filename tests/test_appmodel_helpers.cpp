/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for AppModel pure helpers: mapCategories(). Extracted from
    loadApplications() so it can be unit tested without going through
    KService / KSycoca.
*/

#include <QTest>

#include "appmodel.h"

class TestAppModelHelpers : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void mapsKnownCategoryToBuiltinBucket();
    void mapsMultipleCategoriesToBucket();
    void unknownCategoriesFallToOther();
    void emptyInputReturnsOther();
};

void TestAppModelHelpers::mapsKnownCategoryToBuiltinBucket()
{
    const QStringList result = AppModel::mapCategories({QStringLiteral("Development")});
    QVERIFY(!result.isEmpty());
    QVERIFY(result.contains(QStringLiteral("Development")));
}

void TestAppModelHelpers::mapsMultipleCategoriesToBucket()
{
    const QStringList result = AppModel::mapCategories(
        {QStringLiteral("AudioVideo"), QStringLiteral("Graphics")});
    QVERIFY(result.contains(QStringLiteral("Multimedia")));
    QVERIFY(result.contains(QStringLiteral("Graphics")));
}

void TestAppModelHelpers::unknownCategoriesFallToOther()
{
    const QStringList result = AppModel::mapCategories({QStringLiteral("NotARealCategory")});
    QCOMPARE(result, QStringList{QStringLiteral("Other")});
}

void TestAppModelHelpers::emptyInputReturnsOther()
{
    QCOMPARE(AppModel::mapCategories({}), QStringList{QStringLiteral("Other")});
}

QTEST_MAIN(TestAppModelHelpers)
#include "test_appmodel_helpers.moc"
