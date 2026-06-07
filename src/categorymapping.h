/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QString>

/**
 * Maps a freedesktop .desktop Categories token to one of the
 * AppGrid display buckets (Utilities, Development, Graphics,
 * Internet, Multimedia, Office, Games, Education, System).
 * Returns an empty string when the token is not mapped.
 *
 * The lookup table is built once on first call.
 */
[[nodiscard]] QString mapCategoryToken(const QString &token);

/**
 * Direct read access to the lookup table for unit tests.
 * Returns a reference to the static map.
 */
[[nodiscard]] const QHash<QString, QString> &categoryMap();

/**
 * Maps an AppGrid display bucket (the English token, e.g. "Games",
 * "Utilities", "Other") to the standard freedesktop icon name KDE
 * ships for that menu category (e.g. "applications-games"). Returns
 * "applications-other" for an unknown bucket.
 *
 * Keyed on the untranslated bucket so the lookup is locale-independent;
 * the bar resolves the icon via AppModel, never from the translated
 * label shown to the user. System-categories mode uses the menu group's
 * own .directory icon instead (KServiceGroup::icon()).
 */
[[nodiscard]] QString bucketIcon(const QString &bucket);

/**
 * Direct read access to the bucket → icon table for unit tests.
 */
[[nodiscard]] const QHash<QString, QString> &bucketIconMap();
