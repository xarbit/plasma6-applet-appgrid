/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QSet>
#include <QString>

/**
 * Resolves the user's default applications for the search-ranking boost,
 * separated from AppFilterModel so the "which apps are the user's defaults"
 * concern — reading mimeapps.list, KApplicationTrader and kdeglobals — lives on
 * its own. Stateless: AppFilterModel owns the resulting sets (it needs fast
 * per-row lookup and a test seam), this only computes them.
 */
namespace DefaultAppsResolver
{
struct Result {
    /// Role defaults (browser/mail/file-manager via KApplicationTrader, terminal
    /// via kdeglobals) — outrank everything else in the search tiebreak.
    QSet<QString> preferred;
    /// Every app that is a mimeapps.list default for some type — a weaker boost.
    QSet<QString> defaults;
};

/** Read all sources and resolve the current default-app sets. */
[[nodiscard]] Result resolve();
}
