/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

class KCoreConfigSkeleton;

namespace ConfigAutosave
{
/**
 * Save @p config shortly after any of its settings changes, a burst of
 * changes in one save, and once more when the application quits.
 *
 * KConfigXT setters change the settings in memory only, while the launcher
 * writes settings live (hiding an app, favourites, recents, launch counts).
 * The trigger is every property's NOTIFY signal, not configChanged(): the
 * generated setters emit their own *Changed() signal, configChanged() only
 * fires around save() itself. Connecting every NOTIFY covers each writable
 * key as the schema grows.
 */
void install(KCoreConfigSkeleton *config, int debounceMs = 500);
}
