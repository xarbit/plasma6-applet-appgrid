/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "runnerservice.h"

#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/ResultsModel>
#include <QUrl>

RunnerService::RunnerService(QObject *parent)
    : QObject(parent)
    , m_results(new KRunner::ResultsModel(this))
{
    m_filterModel.setSourceModel(m_results);

    // Order runner results by the user's configured plugin arrangement
    // (krunnerrc [Plugins][Favorites]), the same way KRunner/Kickoff do, and
    // keep it in sync when that config changes (#180). The watcher reparses the
    // shared config before emitting, so re-reading it picks up the change.
    m_krunnerConfig = KSharedConfig::openConfig(QStringLiteral("krunnerrc"));
    applyRunnerFavorites();
    m_krunnerWatcher = KConfigWatcher::create(m_krunnerConfig);
    connect(m_krunnerWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &, const QByteArrayList &) {
        applyRunnerFavorites();
    });
}

void RunnerService::setAppModel(AppFilterModel *apps)
{
    m_filterModel.setAppModel(apps);
}

KRunner::ResultsModel *RunnerService::resultsModel() const
{
    return m_results;
}

RunnerFilterModel *RunnerService::filterModel()
{
    return &m_filterModel;
}

void RunnerService::applyRunnerFavorites()
{
    m_results->setFavoriteIds(PluginHelpers::readRunnerFavorites(m_krunnerConfig));
}

QModelIndex RunnerService::sourceIndex(int row) const
{
    if (row < 0 || row >= m_filterModel.rowCount()) {
        return {};
    }
    return m_filterModel.mapToSource(m_filterModel.index(row, 0));
}

bool RunnerService::run(int row)
{
    const auto index = sourceIndex(row);
    return index.isValid() && m_results->run(index);
}

bool RunnerService::runAction(int row, int actionIndex)
{
    const auto index = sourceIndex(row);
    return index.isValid() && m_results->runAction(index, actionIndex);
}

QString RunnerService::substitutionText(int row) const
{
    const auto index = sourceIndex(row);
    if (!index.isValid()) {
        return {};
    }
    // calculator is the only KRunner plugin where "keep iterating the
    // expression" beats "run and close". Extend the list as other in-place
    // runners earn their place.
    const auto match = m_results->getQueryMatch(index);
    if (!match.runner() || match.runner()->id() != QLatin1String("calculator")) {
        return {};
    }
    return match.text();
}

QString RunnerService::favoriteId(int row) const
{
    const auto index = sourceIndex(row);
    if (!index.isValid()) {
        return {};
    }
    const auto match = m_results->getQueryMatch(index);

    // The services runner puts the canonical id in data(): "applications:<id>" for
    // an app, "applications:<id>?action=<name>" for a jump-list action. Favourite
    // it directly — for an action the query rides along, and the model stores it
    // verbatim instead of collapsing it to the bare app the way Kicker does (#64).
    const QUrl dataUrl = match.data().toUrl();
    if (dataUrl.scheme() == QLatin1String("applications")) {
        return dataUrl.toString();
    }

    // Other runners: a local file/image result (baloo, places). A .desktop URL is
    // an app (the data() path above, or the app model), not a document; remote
    // URLs aren't wired through the UI.
    for (const QUrl &url : match.urls()) {
        if (url.isLocalFile() && !url.path().endsWith(QLatin1String(".desktop"))) {
            return url.toString();
        }
    }
    return {};
}
