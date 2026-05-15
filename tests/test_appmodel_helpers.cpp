/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for AppModel pure helpers: detectInstallSource() and mapCategories().
    These helpers are extracted from loadApplications() so they can be unit
    tested without going through KService / KSycoca.
*/

#include <QTest>

#include "appmodel.h"

class TestAppModelHelpers : public QObject {
    Q_OBJECT
private slots:
    void detectsFlatpakFromExec();
    void detectsFlatpakFromPath();
    void detectsSnapFromExec();
    void detectsSnapFromPath();
    void detectsAppImageCaseInsensitive();
    void detectsWebAppFromAppFlag();
    void detectsWebAppFromAppIdFlag();
    void defaultsToSystem();
    void webAppBeatsFlatpak();

    void mapsKnownCategoryToBuiltinBucket();
    void mapsMultipleCategoriesToBucket();
    void unknownCategoriesFallToOther();
    void emptyInputReturnsOther();
};

void TestAppModelHelpers::detectsFlatpakFromExec()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/flatpak run org.gnome.Gedit"),
                                           QStringLiteral("/usr/share/applications/gedit.desktop")),
             QStringLiteral("Flatpak"));
}

void TestAppModelHelpers::detectsFlatpakFromPath()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("gedit"),
                                           QStringLiteral("/var/lib/flatpak/exports/share/applications/gedit.desktop")),
             QStringLiteral("Flatpak"));
}

void TestAppModelHelpers::detectsSnapFromExec()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/snap/code/123/bin/code"),
                                           QStringLiteral("/usr/share/applications/code.desktop")),
             QStringLiteral("Snap"));
}

void TestAppModelHelpers::detectsSnapFromPath()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("code"),
                                           QStringLiteral("/var/lib/snapd/desktop/applications/code.desktop")),
             QStringLiteral("Snap"));
}

void TestAppModelHelpers::detectsAppImageCaseInsensitive()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/home/u/Apps/Foo.AppImage"), {}),
             QStringLiteral("AppImage"));
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/home/u/Apps/foo.appimage"), {}),
             QStringLiteral("AppImage"));
}

void TestAppModelHelpers::detectsWebAppFromAppFlag()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/chromium --app=https://example.com"), {}),
             QStringLiteral("Web App"));
}

void TestAppModelHelpers::detectsWebAppFromAppIdFlag()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/vivaldi --app-id=abc"), {}),
             QStringLiteral("Web App"));
}

void TestAppModelHelpers::defaultsToSystem()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/kate"),
                                           QStringLiteral("/usr/share/applications/org.kde.kate.desktop")),
             QStringLiteral("System"));
}

void TestAppModelHelpers::webAppBeatsFlatpak()
{
    // Flatpak'd Chromium running as a web app: --app= takes precedence over flatpak.
    QCOMPARE(AppModel::detectInstallSource(
                 QStringLiteral("flatpak run org.chromium.Chromium --app=https://x"),
                 QStringLiteral("/var/lib/flatpak/exports/share/applications/foo.desktop")),
             QStringLiteral("Web App"));
}

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
