/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QLatin1String>
#include <QString>

/**
 * The "applications:" URL KActivities and KAStats use for an app resource,
 * and the one rule for adding and removing it. Mirrors favoriteid.js, so the
 * C++ models and the QML helpers agree.
 */
namespace AppUrl
{
inline constexpr QLatin1String Scheme{"applications:"};

/** The favourite URL for a stored token payload: a bare app storage id gets the
 *  "applications:" scheme; an id that already carries a scheme (a preferred://
 *  favourite) or is a local path (a file favourite, stored bare) is returned
 *  unchanged. */
[[nodiscard]] inline QString toFavoriteId(const QString &payload)
{
    const bool alreadyComplete = payload.contains(QLatin1Char(':')) || payload.startsWith(QLatin1Char('/'));
    return alreadyComplete ? payload : Scheme + payload;
}

/** @p resource with the "applications:" scheme removed if present, else
 *  unchanged. */
[[nodiscard]] inline QString stripScheme(const QString &resource)
{
    return resource.startsWith(Scheme) ? resource.mid(Scheme.size()) : resource;
}
}
