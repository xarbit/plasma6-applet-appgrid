/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppUrl: adding the applications: scheme to an app id, and only to one.
*/

#include <QTest>

#include "appurl.h"

using namespace AppUrl;

class TestAppUrl : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void toFavoriteId_prefixesAppsKeepsTheRest()
    {
        // Bare app storage id → gets the applications: scheme.
        QCOMPARE(toFavoriteId(QStringLiteral("org.kde.dolphin.desktop")), QStringLiteral("applications:org.kde.dolphin.desktop"));
        // An app action id (carries a query, no scheme) still prefixes.
        QCOMPARE(toFavoriteId(QStringLiteral("org.kde.spectacle.desktop?action=Record")),
                 QStringLiteral("applications:org.kde.spectacle.desktop?action=Record"));
        // Already-schemed ids are untouched.
        QCOMPARE(toFavoriteId(QStringLiteral("applications:org.kde.dolphin.desktop")), QStringLiteral("applications:org.kde.dolphin.desktop"));
        QCOMPARE(toFavoriteId(QStringLiteral("preferred://browser")), QStringLiteral("preferred://browser"));
        // A file favourite is stored as a bare path — it must NOT be prefixed,
        // or isFavorite/remove never match the stored row.
        QCOMPARE(toFavoriteId(QStringLiteral("/home/u/pic.png")), QStringLiteral("/home/u/pic.png"));
    }
};

QTEST_GUILESS_MAIN(TestAppUrl)
#include "test_appurl.moc"
