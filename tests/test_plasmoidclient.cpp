/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    PlasmoidClient: an applet-hosted client pins in-process, and the
    settings' button target follows the plasmoid they were opened from. The
    D-Bus side needs a center plasmoid on the bus and is not exercised.
*/

#include "plasmoidclient.h"

#include <QSignalSpy>
#include <QTest>

class TestPlasmoidClient : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void inProcessPinEmitsRequest()
    {
        PlasmoidClient client;
        client.setInProcessPin(true);
        QSignalSpy requested(&client, &PlasmoidClient::addToTaskManagerRequested);

        client.addToTaskManager(QStringLiteral("/usr/share/applications/org.kde.kate.desktop"));
        QCOMPARE(requested.count(), 1);
        QCOMPARE(requested.at(0).at(0).toString(), QStringLiteral("/usr/share/applications/org.kde.kate.desktop"));
        QVERIFY(client.canPinToTaskManager());

        client.addToTaskManager(QString());
        QCOMPARE(requested.count(), 1);
    }

    void buttonTargetFollowsOrigin()
    {
        PlasmoidClient client;
        QSignalSpy changed(&client, &PlasmoidClient::buttonTargetChanged);
        // Launched from a terminal: no plasmoid, no button to edit.
        QVERIFY(!client.canConfigureButton());

        client.setButtonTargetId(QStringLiteral("42"));
        QCOMPARE(changed.count(), 1);
        client.setButtonTargetId(QStringLiteral("42"));
        QCOMPARE(changed.count(), 1);

        client.setButtonTargetId(QString());
        QCOMPARE(changed.count(), 2);
        QVERIFY(!client.canConfigureButton());
    }

    void noTargetFetchesNothing()
    {
        PlasmoidClient client;
        QSignalSpy changed(&client, &PlasmoidClient::buttonAppearanceChanged);
        client.requestButtonAppearance();
        QVERIFY(client.buttonAppearance().isEmpty());
        QCOMPARE(changed.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestPlasmoidClient)
#include "test_plasmoidclient.moc"
