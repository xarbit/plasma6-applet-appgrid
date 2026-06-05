/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "defaultappsresolver.h"

#include "pluginhelpers.h"

#include <KApplicationTrader>
#include <KService>

namespace
{
QString resolvePreferredTerminal()
{
    // Explicit override the terminal KCM writes to kdeglobals (exec line or
    // .desktop id) — resolve it to a storage id.
    const auto overrides = PluginHelpers::loadKdeTerminalDefaults();
    for (const QString &value : overrides) {
        if (const auto byId = KService::serviceByStorageId(value)) {
            return byId->storageId();
        }
        const QString binary = PluginHelpers::execBinaryName(value);
        if (binary.isEmpty()) {
            continue;
        }
        const auto matches = KApplicationTrader::query([&binary](const KService::Ptr &service) {
            return PluginHelpers::execBinaryName(service->exec()) == binary;
        });
        if (!matches.isEmpty()) {
            return matches.first()->storageId();
        }
    }
    // No override means the KCM picked the built-in default and wrote nothing.
    // Mirror KDE's fallback to the first installed standard terminal.
    static const QStringList kFallbackTerminals = {
        QStringLiteral("org.kde.konsole.desktop"),
        QStringLiteral("xterm.desktop"),
    };
    for (const QString &id : kFallbackTerminals) {
        if (const auto svc = KService::serviceByStorageId(id)) {
            return svc->storageId();
        }
    }
    return {};
}

QSet<QString> resolvePreferredRoles()
{
    QSet<QString> resolved;

    // The user's role defaults (browser / mail / file manager), resolved via
    // KApplicationTrader::preferredService — the same resolution System Settings
    // → Default Applications uses, so AppGrid follows the real default as it
    // changes. Only these key roles are boosted: boosting every configured mime
    // pulls in incidental defaults (e.g. the text/plain editor) that then
    // outrank what the user expects for a generic query. (kdeglobals
    // BrowserApplication is a legacy copy that goes stale, so it is not read.)
    static const QStringList kRoleMimeTypes = {
        QStringLiteral("x-scheme-handler/https"),
        QStringLiteral("x-scheme-handler/http"),
        QStringLiteral("x-scheme-handler/mailto"),
        QStringLiteral("inode/directory"),
    };
    for (const QString &mime : kRoleMimeTypes) {
        if (const auto svc = KApplicationTrader::preferredService(mime)) {
            resolved.insert(svc->storageId());
        }
    }

    const QString terminal = resolvePreferredTerminal();
    if (!terminal.isEmpty()) {
        resolved.insert(terminal);
    }
    return resolved;
}
}

DefaultAppsResolver::Result DefaultAppsResolver::resolve()
{
    Result out;
    const auto raw = PluginHelpers::loadMimeAppsDefaults();
    out.defaults = QSet<QString>(raw.cbegin(), raw.cend());
    out.preferred = resolvePreferredRoles();
    return out;
}
