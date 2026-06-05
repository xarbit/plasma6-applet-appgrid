/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appmodelassembly.h"

#include <QCollator>
#include <QHash>
#include <QSet>

#include <algorithm>

AppModelAssembly::Result AppModelAssembly::assemble(const QVector<AppEntry> &occurrences, bool systemMode)
{
    QSet<QString> seen;
    // storageId → index into `apps`, for O(1) "merge category into existing
    // entry" on a repeat occurrence (avoids a linear scan per duplicate on
    // large, heavily-categorised installs).
    QHash<QString, int> seenIndex;
    QSet<QString> categorySet;
    QVector<AppEntry> apps;
    apps.reserve(occurrences.size());

    for (const auto &occ : occurrences) {
        if (occ.storageId.isEmpty()) {
            continue;
        }
        if (seen.contains(occ.storageId)) {
            if (systemMode) {
                const int existingIdx = seenIndex.value(occ.storageId, -1);
                if (existingIdx >= 0) {
                    auto &existing = apps[existingIdx];
                    for (const auto &cat : occ.categories) {
                        if (!existing.categories.contains(cat)) {
                            existing.categories.append(cat);
                            categorySet.insert(cat);
                        }
                    }
                }
            }
            continue;
        }
        seen.insert(occ.storageId);
        // An empty-name occurrence still claims the id (it was marked seen) so a
        // later named duplicate is suppressed, matching the original walk.
        if (occ.name.isEmpty()) {
            continue;
        }

        seenIndex.insert(occ.storageId, apps.size());
        for (const auto &cat : occ.categories) {
            categorySet.insert(cat);
        }
        apps.append(occ);
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(apps.begin(), apps.end(), [&collator](const AppEntry &a, const AppEntry &b) {
        return collator.compare(a.name, b.name) < 0;
    });

    Result result;
    result.apps = std::move(apps);
    result.categories = categorySet.values();
    result.categories.sort();
    return result;
}
