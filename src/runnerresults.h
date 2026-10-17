/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSharedData> // QExplicitlySharedDataPointer (KSharedConfig::Ptr)
#include <QString>
#include <QStringList>
#include <QVariant>

class KSharedConfig;

/**
 * Reading KRunner's results and settings: the app a services-runner result
 * stands for, and the user's favourite runners.
 */
namespace RunnerResults
{
/** First .desktop local-file path from a KRunner row's "urls" role value
 *  (@p urlsData holds a QList<QUrl>), or empty. Maps a services-runner result
 *  back to its desktop file; the caller takes fileName() for the storage id. */
[[nodiscard]] QString desktopPathFromRunnerUrls(const QVariant &urlsData);

/** Storage id (the .desktop basename) for a KRunner row's "urls" role value,
 *  or empty. The fileName() of desktopPathFromRunnerUrls() — one spelling of the
 *  "runner result → app storage id" rule shared by the runner-backed models. */
[[nodiscard]] QString runnerStorageId(const QVariant &urlsData);

/** Ordered favorite runner plugin IDs from a krunnerrc-shaped @p config: the
 *  [Plugins][Favorites] "plugins" entry. These are the runners KRunner pins
 *  first, in this order; AppGrid feeds them to ResultsModel::setFavoriteIds so
 *  its search results follow the same plugin arrangement the user configured
 *  (#180). Empty when unset or @p config is null. The config is passed in
 *  (rather than opened here) so this stays unit-testable against a temp file. */
[[nodiscard]] QStringList readRunnerFavorites(const QExplicitlySharedDataPointer<KSharedConfig> &config);
}
