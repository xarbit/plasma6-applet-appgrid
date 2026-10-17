/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    ServiceAction::find resolves an app action by name, against a KService
    built from a temporary .desktop file.
*/

#include "serviceaction.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class TestServiceAction : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // The context menu lists only actions with text, so launching by the menu's
    // row index picked the wrong action whenever a text-less action came first.
    // Actions are resolved by name instead; a nameless one in front must not
    // shift the result.
    void findsByNamePastNamelessAction()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString path = dir.filePath(QStringLiteral("test-app.desktop"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=Test App\n"
            "Exec=true\n"
            "Actions=blank;second;\n"
            "\n"
            "[Desktop Action blank]\n"
            "Exec=true --blank\n"
            "\n"
            "[Desktop Action second]\n"
            "Name=Second\n"
            "Exec=true --second\n");
        file.close();

        const KService::Ptr service(new KService(path));
        QVERIFY(service->isValid());

        const auto action = ServiceAction::find(service, QStringLiteral("second"));
        QVERIFY(action.has_value());
        QCOMPARE(action->name(), QStringLiteral("second"));
        QCOMPARE(action->text(), QStringLiteral("Second"));

        QVERIFY(!ServiceAction::find(service, QStringLiteral("missing")).has_value());
        QVERIFY(!ServiceAction::find(service, QString()).has_value());
        QVERIFY(!ServiceAction::find(KService::Ptr(), QStringLiteral("second")).has_value());
    }
};

QTEST_GUILESS_MAIN(TestServiceAction)
#include "test_serviceaction.moc"
