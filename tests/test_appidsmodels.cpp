/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The app-id list models. HiddenAppsModel: one row per hidden app from the
    store, following it live; the filter narrows by name or id without
    touching the store; unhide and unhide-all change the store.
    RecentAppsModel: the recents, most recent first, following the store.
*/

#include "hiddenappsmodel.h"
#include "launchstatestore.h"
#include "recentappsmodel.h"

#include <KSharedConfig>

#include <QSignalSpy>
#include <QTest>

class TestAppIdsModels : public QObject
{
    Q_OBJECT

private:
    static QStringList ids(const AppIdsModel &model)
    {
        QStringList out;
        for (int row = 0; row < model.rowCount(); ++row) {
            out << model.data(model.index(row), AppIdsModel::StorageIdRole).toString();
        }
        return out;
    }

private Q_SLOTS:
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
};

QTEST_GUILESS_MAIN(TestAppIdsModels)

#include "test_appidsmodels.moc"
