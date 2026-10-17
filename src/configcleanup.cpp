/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "configcleanup.h"

#include <KConfigGroup>

#include <QStringList>

namespace ConfigCleanup
{
void pruneObsoleteKeys(KConfigGroup &group)
{
    static const QStringList obsolete = {
        QStringLiteral("favoritesPortedToKAstats"),
        QStringLiteral("headerActionsMigrated"),
        QStringLiteral("iconMigratedFrom17"),
        QStringLiteral("powerButtonsMigrated"),
        QStringLiteral("powerButtonsHidden"),
        QStringLiteral("powerButtonOrder"),
        QStringLiteral("showSessionButtons"),
        QStringLiteral("favoriteApps"),
        QStringLiteral("backgroundOpacity"),
        QStringLiteral("cornerRadius"),
        QStringLiteral("enableBackgroundContrast"),
        QStringLiteral("enableBlur"),
        QStringLiteral("openAnimation"),
        QStringLiteral("useThemeBackground"),
        // Old new-app seen-set: replaced by NewAppsTracker's baseline in its own
        // appgridstaterc (installed-apps list + per-app FirstSeen), so this is dead.
        QStringLiteral("knownApps"),
    };
    bool removed = false;
    for (const QString &key : obsolete) {
        if (group.hasKey(key)) {
            group.deleteEntry(key);
            removed = true;
        }
    }
    if (removed) {
        group.sync();
    }
}
}
