/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for RunnerFilterModel: dedup of KRunner results whose display
    name matches a visible app result. Verifies cache rebuild on source
    changes and case-insensitive matching.
*/

#include <QStringListModel>
#include <QTest>

#include "appfiltermodel.h"
#include "runnerfiltermodel.h"
#include "stubappmodel.h"

class TestRunnerFilter : public QObject {
    Q_OBJECT

private slots:
    void init();
    void hidesRunnerRowMatchingAppName();
    void matchIsCaseInsensitive();
    void keepsRunnerRowWhenNoAppMatches();
    void rebuildsCacheOnAppSourceReset();
    void rebuildsCacheOnAppRowsInserted();

private:
    StubAppModel m_appSource;
    AppFilterModel m_appFilter;
    QStringListModel m_runnerSource;
    RunnerFilterModel m_runnerFilter;
};

void TestRunnerFilter::init()
{
    m_appSource.setApps({});
    m_appFilter.setSourceModel(&m_appSource);
    m_runnerSource.setStringList({});
    m_runnerFilter.setSourceModel(&m_runnerSource);
    m_runnerFilter.setAppModel(&m_appFilter);
}

void TestRunnerFilter::hidesRunnerRowMatchingAppName()
{
    m_appSource.setApps({
        {QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("firefox"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Firefox"), QStringLiteral("Calculator")});

    QCOMPARE(m_runnerFilter.rowCount(), 1);
    QCOMPARE(m_runnerFilter.index(0, 0).data(Qt::DisplayRole).toString(),
             QStringLiteral("Calculator"));
}

void TestRunnerFilter::matchIsCaseInsensitive()
{
    m_appSource.setApps({
        {QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("firefox"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("FIREFOX"), QStringLiteral("firefox")});

    QCOMPARE(m_runnerFilter.rowCount(), 0);
}

void TestRunnerFilter::keepsRunnerRowWhenNoAppMatches()
{
    m_appSource.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Calculator"), QStringLiteral("Disks")});

    QCOMPARE(m_runnerFilter.rowCount(), 2);
}

void TestRunnerFilter::rebuildsCacheOnAppSourceReset()
{
    m_runnerSource.setStringList({QStringLiteral("Kate")});
    QCOMPARE(m_runnerFilter.rowCount(), 1);

    m_appSource.setApps({
        {QStringLiteral("Kate"), {}, {}, {}, {}, QStringLiteral("kate"), {}, {}, {}},
    });
    QCOMPARE(m_runnerFilter.rowCount(), 0);

    m_appSource.setApps({});
    QCOMPARE(m_runnerFilter.rowCount(), 1);
}

void TestRunnerFilter::rebuildsCacheOnAppRowsInserted()
{
    m_runnerSource.setStringList({QStringLiteral("Kate"), QStringLiteral("Firefox")});
    QCOMPARE(m_runnerFilter.rowCount(), 2);

    m_appSource.setApps({
        {QStringLiteral("Firefox"), {}, {}, {}, {}, QStringLiteral("firefox"), {}, {}, {}},
    });
    QCOMPARE(m_runnerFilter.rowCount(), 1);
    QCOMPARE(m_runnerFilter.index(0, 0).data(Qt::DisplayRole).toString(),
             QStringLiteral("Kate"));
}

QTEST_MAIN(TestRunnerFilter)
#include "test_runner_filter.moc"
