/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "runnerresults.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QFileInfo>
#include <QList>
#include <QUrl>

namespace RunnerResults
{
QString desktopPathFromRunnerUrls(const QVariant &urlsData)
{
    const auto urls = urlsData.value<QList<QUrl>>();
    for (const auto &url : urls) {
        const auto path = url.toLocalFile();
        if (path.endsWith(QLatin1String(".desktop"))) {
            return path;
        }
    }
    return {};
}

QString runnerStorageId(const QVariant &urlsData)
{
    const QString path = desktopPathFromRunnerUrls(urlsData);
    return path.isEmpty() ? QString() : QFileInfo(path).fileName();
}

QStringList readRunnerFavorites(const QExplicitlySharedDataPointer<KSharedConfig> &config)
{
    if (!config) {
        return {};
    }
    // krunnerrc shape: [Plugins][Favorites] plugins=id1,id2,…
    return config->group(QStringLiteral("Plugins")).group(QStringLiteral("Favorites")).readEntry("plugins", QStringList());
}
}
