/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    ActivityScope: no activity while per-activity favourites are off, and a
    report on each change of that setting. Whether an activity manager runs
    depends on the machine, so what the scope is with it on isn't asserted.
*/

#include "activityscope.h"

#include <QSignalSpy>
#include <QTest>

class TestActivityScope : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void offMeansNoActivity()
    {
        ActivityScope scope;
        QVERIFY(!scope.isEnabled());
        QVERIFY(scope.activity().isEmpty());
    }

    void reportsEachChangeOfTheSetting()
    {
        ActivityScope scope;
        QSignalSpy changed(&scope, &ActivityScope::activityChanged);
        scope.setEnabled(true);
        scope.setEnabled(true);
        QCOMPARE(changed.count(), 1);
        scope.setEnabled(false);
        QCOMPARE(changed.count(), 2);
        QVERIFY(changed.last().at(0).toString().isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestActivityScope)

#include "test_activityscope.moc"
