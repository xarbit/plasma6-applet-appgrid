/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for RunnerFilterModel: dedup of KRunner results whose display
    name matches a visible app result. Verifies cache rebuild on source
    changes and case-insensitive matching.
*/

#include <QStringListModel>
#include <QTest>
#include <QUrl>

#include "appfiltermodel.h"
#include "runnerfiltermodel.h"
#include "stubappmodel.h"

// Minimal KRunner-shaped source exposing a "urls" role (QList<QUrl>) alongside
// DisplayRole, so the hidden-app dedup branch (which reads urls -> .desktop id)
// is actually reachable. QStringListModel can't carry the urls role.
class RunnerStubModel : public QAbstractListModel
{
public:
    static constexpr int UrlsRole = Qt::UserRole + 1;
    struct Row {
        QString display;
        QList<QUrl> urls;
    };

    void setRows(const QVector<Row> &rows)
    {
        beginResetModel();
        m_rows = rows;
        endResetModel();
    }

    int rowCount(const QModelIndex & = {}) const override
    {
        return static_cast<int>(m_rows.size());
    }

    QVariant data(const QModelIndex &idx, int role) const override
    {
        if (!idx.isValid() || idx.row() >= m_rows.size()) {
            return {};
        }
        const auto &r = m_rows.at(idx.row());
        if (role == Qt::DisplayRole) {
            return r.display;
        }
        if (role == UrlsRole) {
            return QVariant::fromValue(r.urls);
        }
        return {};
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return {{Qt::DisplayRole, QByteArrayLiteral("display")}, {UrlsRole, QByteArrayLiteral("urls")}};
    }

private:
    QVector<Row> m_rows;
};

class TestRunnerFilter : public QObject {
    Q_OBJECT

private Q_SLOTS:
    void init();
    void hidesRunnerRowMatchingAppName();
    void matchIsCaseInsensitive();
    void keepsRunnerRowWhenNoAppMatches();
    void rebuildsCacheOnAppSourceReset();
    void rebuildsCacheOnAppRowsInserted();
    void hidesHiddenRunnerRowByDesktopId();
    void keepsHiddenRunnerRowWhenSearchShowsHidden();

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

// A KRunner row for a hidden app (resolved via its urls -> .desktop id) drops
// out when searchShowsHidden is off, mirroring AppFilterModel. This exercises
// the storageIdFromRow / isHidden branch that QStringListModel couldn't reach.
void TestRunnerFilter::hidesHiddenRunnerRowByDesktopId()
{
    RunnerStubModel rich;
    rich.setRows({
        {QStringLiteral("Firefox"), {QUrl(QStringLiteral("file:///usr/share/applications/firefox.desktop"))}},
        {QStringLiteral("Calculator"), {QUrl(QStringLiteral("file:///usr/share/applications/calc.desktop"))}},
    });
    m_runnerFilter.setSourceModel(&rich);
    m_appFilter.setHiddenApps({QStringLiteral("firefox.desktop")});

    // searchShowsHidden defaults off → the hidden row drops, the other stays.
    QCOMPARE(m_runnerFilter.rowCount(), 1);
    QCOMPARE(m_runnerFilter.index(0, 0).data(Qt::DisplayRole).toString(),
             QStringLiteral("Calculator"));
}

void TestRunnerFilter::keepsHiddenRunnerRowWhenSearchShowsHidden()
{
    RunnerStubModel rich;
    rich.setRows({
        {QStringLiteral("Firefox"), {QUrl(QStringLiteral("file:///usr/share/applications/firefox.desktop"))}},
    });
    m_runnerFilter.setSourceModel(&rich);
    m_appFilter.setHiddenApps({QStringLiteral("firefox.desktop")});
    m_appFilter.setSearchShowsHidden(true);

    // Knob on → the hidden gate is skipped, the row survives.
    QCOMPARE(m_runnerFilter.rowCount(), 1);
}

QTEST_MAIN(TestRunnerFilter)
#include "test_runner_filter.moc"
