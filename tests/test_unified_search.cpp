/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tests for UnifiedSearchModel: row concatenation across the app
    proxy and the runner proxy, role mapping for each side, and the
    derived rows (ResultType, IsSectionBoundary, ShortcutNumber,
    SourceIndex).
*/

#include <QStringListModel>
#include <QTest>

#include <KRunner/Action>

#include "appfiltermodel.h"
#include "runnerfiltermodel.h"
#include "stubappmodel.h"
#include "unifiedsearchmodel.h"

// KRunner-shaped source exposing an "actions" role: a QVariantList of
// QVariant-wrapped KRunner::Action, exactly as ResultsModel hands them over.
// QStringListModel can't carry this role, so without it the unwrap loop in
// UnifiedSearchModel::runnerActions never runs.
class RunnerActionsStubModel : public QAbstractListModel
{
public:
    static constexpr int ActionsRole = Qt::UserRole + 1;
    struct Row {
        QString display;
        QVariantList actions;
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
        if (role == ActionsRole) {
            return r.actions;
        }
        return {};
    }

    QHash<int, QByteArray> roleNames() const override
    {
        return {{Qt::DisplayRole, QByteArrayLiteral("display")}, {ActionsRole, QByteArrayLiteral("actions")}};
    }

private:
    QVector<Row> m_rows;
};

class TestUnifiedSearch : public QObject {
    Q_OBJECT

private Q_SLOTS:
    void init();
    void emptyHasZeroRowCount();
    void appOnlyMaps1to1();
    void runnerOnlyMapsToDisplayRole();
    void appBeforeRunnerInRowOrder();
    void sectionBoundaryOnlyOnFirstRunnerRow();
    void sectionBoundaryFalseWhenAppsEmpty();
    void shortcutNumberCapsAtNine();
    void sourceIndexRelativeToEachSide();
    void resultTypeReflectsRowSide();
    void getReturnsAllRolesForRow();
    void dataReturnsEmptyForInvalidIndex();
    void roleNamesContainsAllPublicRoles();
    void runnerActionsEmptyForAppRow();
    void runnerActionsEmptyForOutOfRangeRow();
    void runnerActionsUnwrapsAndSkipsEmpty();

private:
    StubAppModel m_appSource;
    AppFilterModel m_appFilter;
    QStringListModel m_runnerSource;
    RunnerFilterModel m_runnerFilter;
    UnifiedSearchModel m_unified;
};

void TestUnifiedSearch::init()
{
    m_appSource.setApps({});
    m_appFilter.setSourceModel(&m_appSource);
    m_runnerSource.setStringList({});
    m_runnerFilter.setSourceModel(&m_runnerSource);
    m_runnerFilter.setAppModel(&m_appFilter);
    m_unified.setAppModel(&m_appFilter);
    m_unified.setRunnerModel(&m_runnerFilter);
}

void TestUnifiedSearch::emptyHasZeroRowCount()
{
    QCOMPARE(m_unified.rowCount(), 0);
    QCOMPARE(m_unified.appResultCount(), 0);
    QCOMPARE(m_unified.runnerResultCount(), 0);
}

void TestUnifiedSearch::appOnlyMaps1to1()
{
    m_appSource.setApps({
        {QStringLiteral("Firefox"), QStringLiteral("firefox-icon"),
         QStringLiteral("/x/firefox.desktop"), {QStringLiteral("Internet")},
         QStringLiteral("Web Browser"), QStringLiteral("firefox"),
         {}, QStringLiteral("Browse the web"), QStringLiteral("Flatpak")},
    });
    QCOMPARE(m_unified.rowCount(), 1);

    const auto idx = m_unified.index(0, 0);
    QCOMPARE(idx.data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("app"));
    QCOMPARE(idx.data(UnifiedSearchModel::NameRole).toString(),
             QStringLiteral("Firefox"));
    QCOMPARE(idx.data(UnifiedSearchModel::IconRole).toString(),
             QStringLiteral("firefox-icon"));
    // Subtext falls back to GenericName when Comment is empty;
    // here Comment "Browse the web" is set so it wins.
    QCOMPARE(idx.data(UnifiedSearchModel::SubtextRole).toString(),
             QStringLiteral("Browse the web"));
    QCOMPARE(idx.data(UnifiedSearchModel::StorageIdRole).toString(),
             QStringLiteral("firefox"));
    QCOMPARE(idx.data(UnifiedSearchModel::DesktopFileRole).toString(),
             QStringLiteral("/x/firefox.desktop"));
    QCOMPARE(idx.data(UnifiedSearchModel::InstallSourceRole).toString(),
             QStringLiteral("Flatpak"));
}

void TestUnifiedSearch::runnerOnlyMapsToDisplayRole()
{
    m_runnerSource.setStringList({QStringLiteral("Calculator")});
    QCOMPARE(m_unified.rowCount(), 1);

    const auto idx = m_unified.index(0, 0);
    QCOMPARE(idx.data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("runner"));
    QCOMPARE(idx.data(UnifiedSearchModel::NameRole).toString(),
             QStringLiteral("Calculator"));
    // Subtext/category come from dynamic KRunner roles that
    // QStringListModel doesn't expose — read as empty.
    QVERIFY(!idx.data(UnifiedSearchModel::SubtextRole).isValid()
            || idx.data(UnifiedSearchModel::SubtextRole).toString().isEmpty());
}

void TestUnifiedSearch::appBeforeRunnerInRowOrder()
{
    m_appSource.setApps({
        {QStringLiteral("App1"), {}, {}, {}, {}, QStringLiteral("a1"), {}, {}, {}},
        {QStringLiteral("App2"), {}, {}, {}, {}, QStringLiteral("a2"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Runner1")});

    QCOMPARE(m_unified.rowCount(), 3);
    QCOMPARE(m_unified.index(0, 0).data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("app"));
    QCOMPARE(m_unified.index(1, 0).data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("app"));
    QCOMPARE(m_unified.index(2, 0).data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("runner"));
}

void TestUnifiedSearch::sectionBoundaryOnlyOnFirstRunnerRow()
{
    m_appSource.setApps({
        {QStringLiteral("App1"), {}, {}, {}, {}, QStringLiteral("a1"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Runner1"), QStringLiteral("Runner2")});

    QCOMPARE(m_unified.index(0, 0).data(UnifiedSearchModel::IsSectionBoundaryRole).toBool(),
             false);
    QCOMPARE(m_unified.index(1, 0).data(UnifiedSearchModel::IsSectionBoundaryRole).toBool(),
             true);
    QCOMPARE(m_unified.index(2, 0).data(UnifiedSearchModel::IsSectionBoundaryRole).toBool(),
             false);
}

void TestUnifiedSearch::sectionBoundaryFalseWhenAppsEmpty()
{
    // No apps: the first runner row is row 0, not a boundary — there's
    // no app section above it to separate from.
    m_runnerSource.setStringList({QStringLiteral("Runner1")});
    QCOMPARE(m_unified.index(0, 0).data(UnifiedSearchModel::IsSectionBoundaryRole).toBool(),
             false);
}

void TestUnifiedSearch::shortcutNumberCapsAtNine()
{
    QVector<StubApp> apps;
    for (int i = 0; i < 12; ++i) {
        apps.append({QStringLiteral("App%1").arg(i), {}, {}, {}, {},
                     QStringLiteral("a%1").arg(i), {}, {}, {}});
    }
    m_appSource.setApps(apps);

    for (int row = 0; row < 9; ++row) {
        QCOMPARE(m_unified.index(row, 0).data(UnifiedSearchModel::ShortcutNumberRole).toInt(),
                 row + 1);
    }
    for (int row = 9; row < 12; ++row) {
        QCOMPARE(m_unified.index(row, 0).data(UnifiedSearchModel::ShortcutNumberRole).toInt(),
                 0);
    }
}

void TestUnifiedSearch::sourceIndexRelativeToEachSide()
{
    m_appSource.setApps({
        {QStringLiteral("App1"), {}, {}, {}, {}, QStringLiteral("a1"), {}, {}, {}},
        {QStringLiteral("App2"), {}, {}, {}, {}, QStringLiteral("a2"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Runner1"), QStringLiteral("Runner2")});

    // App rows: sourceIndex == row.
    QCOMPARE(m_unified.index(0, 0).data(UnifiedSearchModel::SourceIndexRole).toInt(), 0);
    QCOMPARE(m_unified.index(1, 0).data(UnifiedSearchModel::SourceIndexRole).toInt(), 1);
    // Runner rows: sourceIndex == row - appCount.
    QCOMPARE(m_unified.index(2, 0).data(UnifiedSearchModel::SourceIndexRole).toInt(), 0);
    QCOMPARE(m_unified.index(3, 0).data(UnifiedSearchModel::SourceIndexRole).toInt(), 1);
}

void TestUnifiedSearch::resultTypeReflectsRowSide()
{
    m_appSource.setApps({
        {QStringLiteral("App1"), {}, {}, {}, {}, QStringLiteral("a1"), {}, {}, {}},
    });
    m_runnerSource.setStringList({QStringLiteral("Runner1")});

    QCOMPARE(m_unified.index(0, 0).data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("app"));
    QCOMPARE(m_unified.index(1, 0).data(UnifiedSearchModel::ResultTypeRole).toString(),
             QStringLiteral("runner"));
}

void TestUnifiedSearch::getReturnsAllRolesForRow()
{
    m_appSource.setApps({
        {QStringLiteral("Kate"), QStringLiteral("kate-icon"),
         QStringLiteral("/x/kate.desktop"), {}, {}, QStringLiteral("kate"),
         {}, {}, {}},
    });
    const auto map = m_unified.get(0);
    QCOMPARE(map.value(QStringLiteral("name")).toString(), QStringLiteral("Kate"));
    QCOMPARE(map.value(QStringLiteral("iconName")).toString(), QStringLiteral("kate-icon"));
    QCOMPARE(map.value(QStringLiteral("storageId")).toString(), QStringLiteral("kate"));
    QCOMPARE(map.value(QStringLiteral("resultType")).toString(), QStringLiteral("app"));
}

void TestUnifiedSearch::dataReturnsEmptyForInvalidIndex()
{
    m_appSource.setApps({
        {QStringLiteral("A"), {}, {}, {}, {}, QStringLiteral("a"), {}, {}, {}},
    });
    QVERIFY(!m_unified.index(-1, 0).isValid());
    QVERIFY(m_unified.data(m_unified.index(99, 0),
                            UnifiedSearchModel::NameRole).toString().isEmpty());
}

void TestUnifiedSearch::roleNamesContainsAllPublicRoles()
{
    const auto names = m_unified.roleNames();
    QVERIFY(names.values().contains(QByteArray("name")));
    QVERIFY(names.values().contains(QByteArray("iconName")));
    QVERIFY(names.values().contains(QByteArray("resultType")));
    QVERIFY(names.values().contains(QByteArray("shortcutNumber")));
    QVERIFY(names.values().contains(QByteArray("isSectionBoundary")));
    QVERIFY(names.values().contains(QByteArray("sourceIndex")));
}

void TestUnifiedSearch::runnerActionsEmptyForAppRow()
{
    StubApp app;
    app.name = QStringLiteral("A");
    app.desktopFile = QStringLiteral("a.desktop");
    app.storageId = QStringLiteral("a.desktop");
    m_appSource.setApps({app});
    m_runnerSource.setStringList({QStringLiteral("calc")});
    QCOMPARE(m_unified.runnerActions(0), QVariantList());
}

void TestUnifiedSearch::runnerActionsEmptyForOutOfRangeRow()
{
    QCOMPARE(m_unified.runnerActions(-1), QVariantList());
    QCOMPARE(m_unified.runnerActions(999), QVariantList());
}

void TestUnifiedSearch::runnerActionsUnwrapsAndSkipsEmpty()
{
    RunnerActionsStubModel rich;
    const KRunner::Action valid(QStringLiteral("act1"), QStringLiteral("icon1"), QStringLiteral("Do Thing"));
    const KRunner::Action empty; // id + text empty → dropped by the unwrap filter
    rich.setRows({
        {QStringLiteral("calc"), {QVariant::fromValue(valid), QVariant::fromValue(empty)}},
    });
    m_runnerFilter.setSourceModel(&rich);
    // Re-resolve the actions role: setRunnerModel cached it against the empty
    // QStringListModel from init(), which had no "actions" role.
    m_unified.setRunnerModel(&m_runnerFilter);

    // Row 0 is the runner row (no apps). The empty action is skipped; the valid
    // one is unwrapped into {id, icon, text}.
    const auto actions = m_unified.runnerActions(0);
    QCOMPARE(actions.size(), 1);
    const auto map = actions.first().toMap();
    QCOMPARE(map.value(QStringLiteral("id")).toString(), QStringLiteral("act1"));
    QCOMPARE(map.value(QStringLiteral("icon")).toString(), QStringLiteral("icon1"));
    QCOMPARE(map.value(QStringLiteral("text")).toString(), QStringLiteral("Do Thing"));

    // The count role mirrors the unwrap, also skipping the empty action.
    QCOMPARE(m_unified.data(m_unified.index(0, 0),
                            UnifiedSearchModel::RunnerActionsCountRole).toInt(), 1);
}

QTEST_MAIN(TestUnifiedSearch)
#include "test_unified_search.moc"
