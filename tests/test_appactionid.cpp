/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for AppActionId::parse / hasAction — splitting jump-list action
    favourite ids (applications:<storageId>?action=<name>, #64), and for
    resolveAction() against a KService built from a temporary .desktop file.
*/

#include "appactionid.h"

#include <KService>

#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class TestAppActionId : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void plainIdHasNoAction()
    {
        const auto p = AppActionId::parse(QStringLiteral("org.kde.spectacle.desktop"));
        QCOMPARE(p.storageId, QStringLiteral("org.kde.spectacle.desktop"));
        QVERIFY(p.actionName.isEmpty());
        QVERIFY(!AppActionId::hasAction(QStringLiteral("org.kde.spectacle.desktop")));
    }

    void parsesActionFromBareId()
    {
        const auto p = AppActionId::parse(QStringLiteral("org.kde.spectacle.desktop?action=RecordRegion"));
        QCOMPARE(p.storageId, QStringLiteral("org.kde.spectacle.desktop"));
        QCOMPARE(p.actionName, QStringLiteral("RecordRegion"));
        QVERIFY(AppActionId::hasAction(QStringLiteral("org.kde.spectacle.desktop?action=RecordRegion")));
    }

    void stripsApplicationsScheme()
    {
        const auto p = AppActionId::parse(QStringLiteral("applications:org.kde.spectacle.desktop?action=RecordRegion"));
        QCOMPARE(p.storageId, QStringLiteral("org.kde.spectacle.desktop"));
        QCOMPARE(p.actionName, QStringLiteral("RecordRegion"));
    }

    void schemeWithoutAction()
    {
        const auto p = AppActionId::parse(QStringLiteral("applications:org.kde.spectacle.desktop"));
        QCOMPARE(p.storageId, QStringLiteral("org.kde.spectacle.desktop"));
        QVERIFY(p.actionName.isEmpty());
    }

    void queryWithoutActionKeyIsNoAction()
    {
        const auto p = AppActionId::parse(QStringLiteral("org.kde.spectacle.desktop?foo=bar"));
        QCOMPARE(p.storageId, QStringLiteral("org.kde.spectacle.desktop"));
        QVERIFY(p.actionName.isEmpty());
        QVERIFY(!AppActionId::hasAction(QStringLiteral("org.kde.spectacle.desktop?foo=bar")));
    }

    void emptyId()
    {
        const auto p = AppActionId::parse(QString());
        QVERIFY(p.storageId.isEmpty());
        QVERIFY(p.actionName.isEmpty());
        QVERIFY(!AppActionId::hasAction(QString()));
    }

    // The context menu lists only actions with text, so launching by the menu's
    // row index picked the wrong action whenever a text-less action came first.
    // Actions are resolved by name instead; a nameless one in front must not
    // shift the result.
    void resolvesActionByNamePastNamelessAction()
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

        const auto action = AppActionId::resolveAction(service, QStringLiteral("second"));
        QVERIFY(action.has_value());
        QCOMPARE(action->name(), QStringLiteral("second"));
        QCOMPARE(action->text(), QStringLiteral("Second"));

        QVERIFY(!AppActionId::resolveAction(service, QStringLiteral("missing")).has_value());
        QVERIFY(!AppActionId::resolveAction(service, QString()).has_value());
        QVERIFY(!AppActionId::resolveAction(KService::Ptr(), QStringLiteral("second")).has_value());
    }
};

QTEST_MAIN(TestAppActionId)
#include "test_appactionid.moc"
