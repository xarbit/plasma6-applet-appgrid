/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    AppletMigration: an older applet's settings copy into appgridrc once and
    only once, and its launch lists seed only what the store lacks. Also the
    flags a plasmoid starts the daemon with on its own behalf.
*/

#include "appletmigration.h"
#include "launchstatestore.h"
#include "standaloneclient.h"

#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>

#include <QTemporaryDir>
#include <QTest>

class TestAppletMigration : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void settingsCopyOnce()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        KConfig applet(dir.filePath(QStringLiteral("appletrc")), KConfig::SimpleConfig);
        KConfigGroup general = applet.group(QStringLiteral("General"));
        general.writeEntry("gridColumns", 7);

        KConfig appgridrc(dir.filePath(QStringLiteral("appgridrc")), KConfig::SimpleConfig);
        AppletMigration::copySettingsToStandalone(general, appgridrc);
        QCOMPARE(appgridrc.group(QStringLiteral("General")).readEntry("gridColumns", 0), 7);

        // A later change in the applet no longer reaches the daemon.
        general.writeEntry("gridColumns", 3);
        AppletMigration::copySettingsToStandalone(general, appgridrc);
        QCOMPARE(appgridrc.group(QStringLiteral("General")).readEntry("gridColumns", 0), 7);
    }

    void launchStateSeedsOnlyWhatIsMissing()
    {
        LaunchStateStore store(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig));
        store.setRecentApps({QStringLiteral("kept.desktop")});

        KConfig applet(QString(), KConfig::SimpleConfig);
        KConfigGroup general = applet.group(QStringLiteral("General"));
        general.writeEntry("hiddenApps", QStringList{QStringLiteral("h.desktop")});
        general.writeEntry("recentApps", QStringList{QStringLiteral("old.desktop")});
        general.writeEntry("launchCounts", QStringList{QStringLiteral("h.desktop=4")});

        AppletMigration::moveLaunchState(general, store);
        QCOMPARE(store.hiddenApps(), QStringList{QStringLiteral("h.desktop")});
        QCOMPARE(store.recentApps(), QStringList{QStringLiteral("kept.desktop")});
        QCOMPARE(store.book().launchCount(QStringLiteral("h.desktop")), 4);
    }

    void ownerLaunchArgsCarryTheId()
    {
        QCOMPARE(StandaloneClient::ownerLaunchArgs(QStringLiteral("12"), {QStringLiteral("--configure")}),
                 QStringList({QStringLiteral("--configure"), QStringLiteral("--plasmoid-id=12")}));
        QCOMPARE(StandaloneClient::ownerLaunchArgs(QStringLiteral("12"), {}), QStringList{QStringLiteral("--plasmoid-id=12")});
    }
};

QTEST_GUILESS_MAIN(TestAppletMigration)

#include "test_appletmigration.moc"
