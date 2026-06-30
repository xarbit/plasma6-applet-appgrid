/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "frecencyscoring.h"

#include "pluginhelpers.h"

namespace
{
// Only app resources score (a file/document favourite has no storage id here);
// non-app resources return empty and are skipped by the caller.
QString storageIdFromResource(const QString &resource)
{
    return resource.startsWith(PluginHelpers::ApplicationsUrlPrefix) ? PluginHelpers::stripApplicationsPrefix(resource) : QString();
}
}

QHash<QString, int> FrecencyScoring::scoresFromResources(const QStringList &orderedResources)
{
    const int rows = orderedResources.size();
    QHash<QString, int> scores;
    scores.reserve(static_cast<qsizetype>(rows) * 2);
    const QLatin1String kdePrefix("org.kde.");
    // Insert keyed by `key`, but never demote an existing higher score (matters
    // when two distinct apps collide on the normalised form).
    const auto add = [&scores](const QString &key, int score) {
        if (key.isEmpty()) {
            return;
        }
        const auto it = scores.find(key);
        if (it == scores.end() || it.value() < score) {
            scores.insert(key, score);
        }
    };
    for (int r = 0; r < rows; ++r) {
        const QString sid = storageIdFromResource(orderedResources.at(r));
        if (sid.isEmpty()) {
            continue;
        }
        // Rank-based score (top row = `rows`, last row = 1).
        const int score = rows - r;
        add(sid, score);
        // Same app, two common .desktop id shapes — index both spellings so the
        // AppFilterModel lookup hits regardless of which AppModel reports.
        if (sid.startsWith(kdePrefix)) {
            add(sid.mid(kdePrefix.size()), score);
        } else {
            add(kdePrefix + sid, score);
        }
    }
    return scores;
}
