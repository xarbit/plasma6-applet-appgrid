/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unit tests for AppGridStandalone's D-Bus surface: every method of the
    interface, called through the adaptor generated from its XML, emits its
    matching Qt signal (the QML entry / main.cpp wire these), and Version()
    reports the build the daemon was compiled as (the plasmoid's stale-daemon
    check compares against it). Registration is not exercised — it needs a live
    session bus — only the method→signal mapping, which is pure.
*/

#include <QSignalSpy>
#include <QTest>

#include "appgridstandalone.h"
#include "standaloneadaptor.h"

class TestAppGridStandalone : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void methodsEmitSignals_data();
    void methodsEmitSignals();
    void versionIsBuildVersion();
};

void TestAppGridStandalone::methodsEmitSignals_data()
{
    QTest::addColumn<QByteArray>("method");
    QTest::addColumn<QByteArray>("signal");

    QTest::newRow("Show") << QByteArray("Show") << QByteArray(SIGNAL(showRequested()));
    QTest::newRow("Hide") << QByteArray("Hide") << QByteArray(SIGNAL(hideRequested()));
    QTest::newRow("Toggle") << QByteArray("Toggle") << QByteArray(SIGNAL(toggleRequested(QString)));
    QTest::newRow("ToggleCompact") << QByteArray("ToggleCompact") << QByteArray(SIGNAL(toggleCompactRequested(QString)));
    QTest::newRow("Configure") << QByteArray("Configure") << QByteArray(SIGNAL(configureRequested(QString)));
    QTest::newRow("Quit") << QByteArray("Quit") << QByteArray(SIGNAL(quitRequested()));
}

void TestAppGridStandalone::methodsEmitSignals()
{
    QFETCH(QByteArray, method);
    QFETCH(QByteArray, signal);

    AppGridStandalone standalone;
    auto *adaptor = new StandaloneAdaptor(&standalone);
    QSignalSpy spy(&standalone, signal.constData());
    QVERIFY(spy.isValid());
    QVERIFY(QMetaObject::invokeMethod(adaptor, method.constData()));
    QCOMPARE(spy.count(), 1);
}

void TestAppGridStandalone::versionIsBuildVersion()
{
    AppGridStandalone standalone;
    auto *adaptor = new StandaloneAdaptor(&standalone);
    QCOMPARE(adaptor->Version(), QStringLiteral(APPGRID_VERSION));
    QVERIFY(!adaptor->Version().isEmpty());
}

QTEST_GUILESS_MAIN(TestAppGridStandalone)
#include "test_standalone.moc"
