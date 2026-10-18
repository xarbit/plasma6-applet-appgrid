/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The app-id list models. HiddenAppsModel: one row per hidden app from the
    store, following it live; the filter narrows by name or id without
    touching the store; unhide and unhide-all change the store.
    RecentAppsModel: the recents, most recent first, following the store; an
    app uninstalled while in the recents loses its name, so its tile hides.
*/

#include "hiddenappsmodel.h"
#include "launchstatestore.h"
#include "recentappsmodel.h"

#include <KService>
#include <KSharedConfig>
#include <KSycoca>

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>

class TestAppIdsModels : public QObject
{
    Q_OBJECT

private:
    QString m_recentDesktopFile;

    static QStringList ids(const AppIdsModel &model)
    {
        QStringList out;
        for (int row = 0; row < model.rowCount(); ++row) {
            out << model.data(model.index(row), AppIdsModel::StorageIdRole).toString();
        }
        return out;
    }

private Q_SLOTS:
    void initTestCase()
    {
        // Install the app before anything opens KSycoca, so its first load
        // already knows it.
        QStandardPaths::setTestModeEnabled(true);
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/applications");
        QVERIFY(QDir().mkpath(dir));
        m_recentDesktopFile = dir + QStringLiteral("/appgrid-test-recent.desktop");
        QFile file(m_recentDesktopFile);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write("[Desktop Entry]\nType=Application\nName=AppGrid Test Recent\nExec=true\n");
        file.close();
        KSycoca::self()->ensureCacheValid();
    }

    void cleanupTestCase()
    {
        QFile::remove(m_recentDesktopFile);
    }

    void followsTheStore()
    {
        LaunchStateStore store(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig));
        HiddenAppsModel model;
        QVERIFY(model.isEmpty());
        model.setLaunchState(&store);
        store.hide(QStringLiteral("appgrid-test-a.desktop"));
        store.hide(QStringLiteral("appgrid-test-b.desktop"));
        QCOMPARE(ids(model), QStringList({QStringLiteral("appgrid-test-a.desktop"), QStringLiteral("appgrid-test-b.desktop")}));
        // Nothing resolves these ids: the name falls back to the id.
        QCOMPARE(model.data(model.index(0), HiddenAppsModel::NameRole).toString(), QStringLiteral("appgrid-test-a.desktop"));

        model.unhide(QStringLiteral("appgrid-test-a.desktop"));
        QCOMPARE(store.hiddenApps(), QStringList{QStringLiteral("appgrid-test-b.desktop")});
        QCOMPARE(model.rowCount(), 1);
        model.unhideAll();
        QVERIFY(store.hiddenApps().isEmpty());
        QVERIFY(model.isEmpty());
    }

    void filterNarrowsTheRowsOnly()
    {
        LaunchStateStore store(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig));
        store.setHiddenApps({QStringLiteral("appgrid-test-kate.desktop"), QStringLiteral("appgrid-test-gimp.desktop")});
        HiddenAppsModel model;
        model.setLaunchState(&store);
        QSignalSpy count(&model, &HiddenAppsModel::countChanged);
        model.setFilter(QStringLiteral("GIMP"));
        QCOMPARE(ids(model), QStringList{QStringLiteral("appgrid-test-gimp.desktop")});
        QVERIFY(!model.isEmpty());
        QVERIFY(count.count() > 0);
        QCOMPARE(store.hiddenApps().size(), 2);
        model.setFilter(QStringLiteral("nothing"));
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(!model.isEmpty());
    }

    void recentsFollowTheStore()
    {
        LaunchStateStore store(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig));
        RecentAppsModel model;
        model.setLaunchState(&store);
        QCOMPARE(model.rowCount(), 0);
        store.recordLaunch(QStringLiteral("appgrid-test-a.desktop"), 6);
        store.recordLaunch(QStringLiteral("appgrid-test-b.desktop"), 6);
        QCOMPARE(ids(model), QStringList({QStringLiteral("appgrid-test-b.desktop"), QStringLiteral("appgrid-test-a.desktop")}));
        // Nothing resolves these ids: no name, so the row stays unseen.
        QVERIFY(model.data(model.index(0), AppIdsModel::NameRole).toString().isEmpty());
        model.setLaunchState(nullptr);
        QCOMPARE(model.rowCount(), 0);
    }

    // The .desktop file of a recent app is removed (a browser deleting its web
    // app): once KSycoca has rebuilt and announced it, the row has no name any
    // more, and the recents row hides a tile without one.
    void uninstalledRecentLosesItsName()
    {
        const QString id = QStringLiteral("appgrid-test-recent.desktop");
        LaunchStateStore store(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig));
        RecentAppsModel model;
        model.setLaunchState(&store);
        store.recordLaunch(id, 6);
        QCOMPARE(model.data(model.index(0), AppIdsModel::NameRole).toString(), QStringLiteral("AppGrid Test Recent"));

        // KSycoca compares directory times to the second; remove the file in a
        // later second than the install so the rebuild sees it.
        QTest::qSleep(1100);
        QVERIFY(QFile::remove(m_recentDesktopFile));
        QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
        const auto rebuilt = [&id] {
            KSycoca::self()->ensureCacheValid();
            return !KService::serviceByStorageId(id);
        };
        QTRY_VERIFY(rebuilt());
        QTRY_VERIFY(changed.count() > 0);
        QVERIFY(model.data(model.index(0), AppIdsModel::NameRole).toString().isEmpty());
        QCOMPARE(ids(model), QStringList({id}));
    }
};

QTEST_GUILESS_MAIN(TestAppIdsModels)

#include "test_appidsmodels.moc"
