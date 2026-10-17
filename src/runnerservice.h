/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "runnerfiltermodel.h"

#include <KConfigWatcher>
#include <KSharedConfig>
#include <QObject>

namespace KRunner
{
class ResultsModel;
}

class AppFilterModel;

/**
 * @brief KRunner search for the launcher: the results, and running them.
 *
 * Owns the KRunner results model (ordered by the user's krunnerrc plugin
 * arrangement, like KRunner and Kickoff) and the filter that drops results
 * the app grid already shows. The run methods take a row of that filter
 * model, the index QML sees.
 */
class RunnerService : public QObject
{
    Q_OBJECT

public:
    explicit RunnerService(QObject *parent = nullptr);

    /** The apps the filter model leaves out of the runner results. */
    void setAppModel(AppFilterModel *apps);

    /** The KRunner results; QML sets its queryString. */
    [[nodiscard]] KRunner::ResultsModel *resultsModel() const;
    /** The results without the apps the grid already shows. */
    [[nodiscard]] RunnerFilterModel *filterModel();

    /** Run the result at @p row. Returns true if the UI should close. */
    Q_INVOKABLE bool run(int row);
    /** Run secondary action @p actionIndex of the result at @p row. */
    Q_INVOKABLE bool runAction(int row, int actionIndex);
    /** Substitution text for in-place results (calculator), else empty. */
    [[nodiscard]] Q_INVOKABLE QString substitutionText(int row) const;
    /** The favourite id of the result at @p row (#64): its "applications:"
     *  URL for an app or System Settings module, its file URL for a local
     *  file; empty when it has none (a calculator answer). */
    [[nodiscard]] Q_INVOKABLE QString favoriteId(int row) const;

private:
    void applyRunnerFavorites();
    [[nodiscard]] QModelIndex sourceIndex(int row) const;

    KRunner::ResultsModel *m_results = nullptr;
    RunnerFilterModel m_filterModel;
    KSharedConfig::Ptr m_krunnerConfig;
    KConfigWatcher::Ptr m_krunnerWatcher;
};
