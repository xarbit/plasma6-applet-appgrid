/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appletmigration.h"

#include "launchstatestore.h"

#include <KConfig>
#include <KConfigGroup>

namespace AppletMigration
{
void copySettingsToStandalone(const KConfigGroup &appletGeneral, KConfig &appgridrc)
{
    KConfigGroup marker = appgridrc.group(QStringLiteral("Migration"));
    if (marker.readEntry("fromPlasmoid", false)) {
        return; // already migrated — the daemon owns appgridrc now
    }
    // Same schema, same keys: the applet's [General] copies over as is.
    KConfigGroup general = appgridrc.group(QStringLiteral("General"));
    appletGeneral.copyTo(&general);
    marker.writeEntry("fromPlasmoid", true);
    appgridrc.sync();
}

void moveLaunchState(const KConfigGroup &appletGeneral, LaunchStateStore &store)
{
    // The same keys, even though the applet's schema no longer maps them.
    store.migrateFrom(appletGeneral.readEntry("hiddenApps", QStringList()),
                      appletGeneral.readEntry("recentApps", QStringList()),
                      appletGeneral.readEntry("launchCounts", QStringList()));
}
}
