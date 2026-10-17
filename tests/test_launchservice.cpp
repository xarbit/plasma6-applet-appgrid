/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppResolver and LaunchService: the parts that need no running desktop —
    resolving documents and unknown ids, the key a launch is recorded under,
    and refusing what resolves to nothing (no launch, nothing recorded).
*/

#include "appresolver.h"
#include "launchservice.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class TestLaunchService : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void launchKeyStripsPrefixAndKeepsAction()
    {
        QCOMPARE(LaunchService::launchKey(QStringLiteral("org.kde.kate.desktop")), QStringLiteral("org.kde.kate.desktop"));
        QCOMPARE(LaunchService::launchKey(QStringLiteral("applications:org.kde.kate.desktop")), QStringLiteral("org.kde.kate.desktop"));
        QCOMPARE(LaunchService::launchKey(QStringLiteral("applications:org.kde.kate.desktop?action=newWindow")),
                 QStringLiteral("org.kde.kate.desktop?action=newWindow"));
    }

    void launchKeyIsEmptyForDocumentsAndNothing()
    {
        QVERIFY(LaunchService::launchKey(QString()).isEmpty());
        QVERIFY(LaunchService::launchKey(QStringLiteral("/home/user/notes.txt")).isEmpty());
        QVERIFY(LaunchService::launchKey(QStringLiteral("file:///home/user/notes.txt")).isEmpty());
    }

    void resolvesExistingDocument()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath(QStringLiteral("notes.txt"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("hello\n");
        file.close();

        const AppResolver::Target target = AppResolver::resolve(path);
        QVERIFY(target.isValid());
        QVERIFY(!target.service);
        QCOMPARE(target.documentUrl, QUrl::fromLocalFile(path));
        QCOMPARE(target.name, QStringLiteral("notes.txt"));
        QCOMPARE(target.icon, QStringLiteral("text-plain"));
        QVERIFY(AppResolver::resolve(QUrl::fromLocalFile(path).toString()).isValid());
    }

    void missingDocumentAndUnknownAppDoNotResolve()
    {
        QVERIFY(!AppResolver::resolve(QString()).isValid());
        QVERIFY(!AppResolver::resolve(QStringLiteral("/nonexistent/appgrid-test/notes.txt")).isValid());
        QVERIFY(!AppResolver::resolve(QStringLiteral("appgrid-test-nonexistent.desktop")).isValid());
        QVERIFY(!AppResolver::resolve(QStringLiteral("applications:appgrid-test-nonexistent.desktop?action=x")).isValid());
        QVERIFY(AppResolver::actions(KService::Ptr()).isEmpty());
    }

    void unresolvableLaunchRecordsNothing()
    {
        LaunchService service;
        QSignalSpy launched(&service, &LaunchService::appLaunched);
        QVERIFY(!service.launch(QString()));
        QVERIFY(!service.launch(QStringLiteral("appgrid-test-nonexistent.desktop")));
        QVERIFY(!service.launch(QStringLiteral("/nonexistent/appgrid-test/notes.txt")));
        QVERIFY(!service.launchAction(QStringLiteral("appgrid-test-nonexistent.desktop"), QStringLiteral("x")));
        QVERIFY(!service.launchAction(QString(), QStringLiteral("x")));
        QCOMPARE(launched.count(), 0);
        QVERIFY(service.appActions(QStringLiteral("appgrid-test-nonexistent.desktop")).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestLaunchService)

#include "test_launchservice.moc"
