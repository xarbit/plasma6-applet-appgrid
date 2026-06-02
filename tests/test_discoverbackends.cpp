/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for the DiscoverBackends install-source ↔ backend ↔ tool
    mapping extracted from AppGridPlugin.
*/

#include <QTest>

#include "discoverbackends.h"

class TestDiscoverBackends : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void forInstallSource_maps();
    void toolForBackend_maps();
    void isBackendInstalled_falseForUnknown();
};

void TestDiscoverBackends::forInstallSource_maps()
{
    using namespace DiscoverBackends;
    QCOMPARE(forInstallSource(QStringLiteral("System")), QStringLiteral("packagekit"));
    QCOMPARE(forInstallSource(QStringLiteral("Flatpak")), QStringLiteral("flatpak"));
    QCOMPARE(forInstallSource(QStringLiteral("Snap")), QStringLiteral("snap"));
    QVERIFY(forInstallSource(QStringLiteral("Web App")).isEmpty());
    QVERIFY(forInstallSource(QString()).isEmpty());
}

void TestDiscoverBackends::toolForBackend_maps()
{
    using namespace DiscoverBackends;
    QCOMPARE(toolForBackend(QStringLiteral("flatpak")), QStringLiteral("flatpak"));
    QCOMPARE(toolForBackend(QStringLiteral("snap")), QStringLiteral("snap"));
    // PackageKit is gated by a D-Bus service, not a CLI.
    QVERIFY(toolForBackend(QStringLiteral("packagekit")).isEmpty());
}

void TestDiscoverBackends::isBackendInstalled_falseForUnknown()
{
    // No "nonexistent-backend.so" in any library path → false, deterministic.
    QVERIFY(!DiscoverBackends::isBackendInstalled(QStringLiteral("nonexistent")));
}

QTEST_GUILESS_MAIN(TestDiscoverBackends)
#include "test_discoverbackends.moc"
