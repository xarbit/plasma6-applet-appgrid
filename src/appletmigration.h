/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

class KConfig;
class KConfigGroup;
class LaunchStateStore;

/**
 * One-shot moves of what an older applet kept in its own config to where it
 * lives now. Both are idempotent.
 */
namespace AppletMigration
{
/** Copy the applet's settings (@p appletGeneral, its [Configuration][General])
 *  into the standalone daemon's config @p appgridrc the first time only, so a
 *  user upgrading from the in-process center variant keeps their settings.
 *  Flagged in @p appgridrc; after that the daemon owns it. */
void copySettingsToStandalone(const KConfigGroup &appletGeneral, KConfig &appgridrc);

/** Seed @p store from the applet's old per-applet hidden / recent /
 *  launch-count lists in @p appletGeneral. The store fills only the lists it
 *  doesn't already hold, so it never clobbers the daemon's or another
 *  applet's. */
void moveLaunchState(const KConfigGroup &appletGeneral, LaunchStateStore &store);
}
