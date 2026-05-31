/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>

#include "appfiltermodel.h"
#include "runnerfiltermodel.h"

/**
 * @brief Unified search model combining app results and KRunner results.
 *
 * Concatenates AppFilterModel rows (apps) with RunnerFilterModel rows
 * (KRunner) into a single list with unified role names. Enables one
 * ListView for all search results.
 */
class UnifiedSearchModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int appResultCount READ appResultCount NOTIFY layoutChanged)
    Q_PROPERTY(int runnerResultCount READ runnerResultCount NOTIFY layoutChanged)

public:
    enum Roles {
        ResultTypeRole = Qt::UserRole + 100,
        NameRole,
        IconRole,
        SubtextRole,
        CategoryRole,
        StorageIdRole,
        DesktopFileRole,
        IsNewRole,
        ShortcutNumberRole,
        IsSectionBoundaryRole,
        SourceIndexRole,
        InstallSourceRole,
        RunnerActionsCountRole,
    };
    Q_ENUM(Roles)

    explicit UnifiedSearchModel(QObject *parent = nullptr);

    void setAppModel(AppFilterModel *model);
    void setRunnerModel(RunnerFilterModel *model);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    [[nodiscard]] int appResultCount() const;
    [[nodiscard]] int runnerResultCount() const;

    [[nodiscard]] Q_INVOKABLE QVariantMap get(int row) const;

    // Secondary actions for a KRunner row (e.g. calculator "Copy result").
    // Empty list for app rows or when the runner provides no actions.
    // Each entry is {id, icon, text} so QML can populate a menu directly.
    [[nodiscard]] Q_INVOKABLE QVariantList runnerActions(int row) const;

private Q_SLOTS:
    void onSourceChanged();
    void doReset();

private:
    AppFilterModel *m_appModel = nullptr;
    RunnerFilterModel *m_runnerModel = nullptr;
    int m_runnerSubtextRole = -1;
    int m_runnerCategoryRole = -1;
    int m_runnerUrlsRole = -1;
    int m_runnerActionsRole = -1;
    bool m_resetPending = false;
};
