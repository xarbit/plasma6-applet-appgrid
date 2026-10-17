/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

class KConfigGroup;

namespace ConfigCleanup
{
/** One-time tidy of @p group: drop keys older versions wrote that no current
 *  code reads — 1.x→2.0 migration flags and appearance settings removed in the
 *  2.0 window rework. Used for both appgridrc [General] and the applet's own
 *  config group. Idempotent; syncs only when something was removed. */
void pruneObsoleteKeys(KConfigGroup &group);
}
