/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    InstallSource::detect: where an app came from, from its exec line, its
    installed path and the keys Flatpak and snapd write into it.
*/

#include "installsource.h"

#include <QTest>

using InstallSource::detect;

class TestInstallSource : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void flatpak()
    {
        QCOMPARE(detect(QStringLiteral("/usr/bin/flatpak run org.gnome.Gedit"), QStringLiteral("/usr/share/applications/gedit.desktop")),
                 QStringLiteral("Flatpak"));
        QCOMPARE(detect(QStringLiteral("gedit"), QStringLiteral("/var/lib/flatpak/exports/share/applications/gedit.desktop")), QStringLiteral("Flatpak"));
        QCOMPARE(detect(QStringLiteral("gedit"), QStringLiteral("/home/u/.local/share/flatpak/exports/share/applications/gedit.desktop")),
                 QStringLiteral("Flatpak"));
        QCOMPARE(detect(QStringLiteral("gedit"), QStringLiteral("/somewhere/gedit.desktop"), QStringLiteral("org.gnome.Gedit")), QStringLiteral("Flatpak"));
    }

    void snap()
    {
        QCOMPARE(detect(QStringLiteral("/snap/code/123/bin/code"), QStringLiteral("/usr/share/applications/code.desktop")), QStringLiteral("Snap"));
        QCOMPARE(detect(QStringLiteral("code"), QStringLiteral("/var/lib/snapd/desktop/applications/code_code.desktop")), QStringLiteral("Snap"));
        QCOMPARE(detect(QStringLiteral("code"), QStringLiteral("/somewhere/code.desktop"), {}, QStringLiteral("code")), QStringLiteral("Snap"));
    }

    // A name that only contains "snap" or "flatpak" is not a sandboxed app.
    void namesAreNotSources()
    {
        QCOMPARE(detect(QStringLiteral("snapper-gui"), QStringLiteral("/usr/share/applications/snapper-gui.desktop")), QStringLiteral("System"));
        QCOMPARE(detect(QStringLiteral("snapshot"), QStringLiteral("/usr/share/applications/org.gnome.Snapshot.desktop")), QStringLiteral("System"));
        QCOMPARE(detect(QStringLiteral("flatpak-builder-gui"), QStringLiteral("/usr/share/applications/flatpak-builder-gui.desktop")),
                 QStringLiteral("System"));
    }

    void appImage()
    {
        QCOMPARE(detect(QStringLiteral("/home/u/Apps/Foo.AppImage"), {}), QStringLiteral("AppImage"));
        QCOMPARE(detect(QStringLiteral("/home/u/Apps/foo.appimage"), {}), QStringLiteral("AppImage"));
    }

    void webApp()
    {
        QCOMPARE(detect(QStringLiteral("/usr/bin/chromium --app=https://example.com"), {}), QStringLiteral("Web App"));
        QCOMPARE(detect(QStringLiteral("/usr/bin/vivaldi --app-id=abc"), {}), QStringLiteral("Web App"));
        // A web app in a Flatpak browser is still a web app.
        QCOMPARE(detect(QStringLiteral("flatpak run org.chromium.Chromium --app=https://x"),
                        QStringLiteral("/var/lib/flatpak/exports/share/applications/foo.desktop"),
                        QStringLiteral("org.chromium.Chromium")),
                 QStringLiteral("Web App"));
    }

    void system()
    {
        QCOMPARE(detect(QStringLiteral("/usr/bin/kate"), QStringLiteral("/usr/share/applications/org.kde.kate.desktop")), QStringLiteral("System"));
        QVERIFY(InstallSource::of(KService::Ptr()).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestInstallSource)

#include "test_installsource.moc"
