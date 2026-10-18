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
private Q_SLOTS:
    void detectsFlatpakFromExec();
    void detectsFlatpakFromPath();
    void detectsSnapFromExec();
    void detectsSnapFromPath();
    void detectsAppImageCaseInsensitive();
    void detectsWebAppFromAppFlag();
    void detectsWebAppFromAppIdFlag();
    void defaultsToSystem();
    void webAppBeatsFlatpak();
    void nameContainingSnapIsSystem();
    void nameContainingFlatpakIsSystem();
    void distroPackageWithFlatpakKeyIsSystem();
    void copiedFlatpakEntryIsFlatpak();

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

void TestAppModelHelpers::nameContainingSnapIsSystem()
{
    // Seen on a real install with no snapd: a Limine/snapper tool and
    // Discover's own Snap helper entry are distro packages.
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/limine-snapper-restore"),
                                           QStringLiteral("/usr/share/applications/limine-snapper-restore.desktop")),
             QStringLiteral("System"));
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("plasma-discover --backends snap-backend"),
                                           QStringLiteral("/usr/share/applications/org.kde.discover.snap.desktop")),
             QStringLiteral("System"));
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("snapshot"),
                                           QStringLiteral("/usr/share/applications/org.gnome.Snapshot.desktop")),
             QStringLiteral("System"));
}

void TestAppModelHelpers::nameContainingFlatpakIsSystem()
{
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/flatpak-builder-gui"),
                                           QStringLiteral("/usr/share/applications/flatpak-builder-gui.desktop")),
             QStringLiteral("System"));
}

void TestAppModelHelpers::distroPackageWithFlatpakKeyIsSystem()
{
    // podman-desktop from the distro ships upstream's .desktop file, which
    // carries X-Flatpak; Exec and path say System.
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("podman-desktop %U"),
                                           QStringLiteral("/usr/share/applications/io.podman_desktop.PodmanDesktop.desktop")),
             QStringLiteral("System"));
}

void TestAppModelHelpers::copiedFlatpakEntryIsFlatpak()
{
    // A Flatpak's .desktop copied to ~/.local/share/applications still runs it.
    QCOMPARE(AppModel::detectInstallSource(QStringLiteral("/usr/bin/flatpak run --branch=master ch.threema.threema-desktop"),
                                           QStringLiteral("/home/u/.local/share/applications/ch.threema.threema-desktop.desktop")),
             QStringLiteral("Flatpak"));
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
