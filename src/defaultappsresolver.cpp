/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "defaultappsresolver.h"

#include <KApplicationTrader>
#include <KConfig>
#include <KConfigGroup>
#include <KService>
#include <KSharedConfig>

#include <QSet>
#include <QStandardPaths>

#include <utility>

namespace
{
QString resolvePreferredTerminal()
{
    // Explicit override the terminal KCM writes to kdeglobals (exec line or
    // .desktop id) — resolve it to a storage id.
    const auto overrides = DefaultAppsResolver::loadKdeTerminalDefaults();
    for (const QString &value : overrides) {
        if (const auto byId = KService::serviceByStorageId(value)) {
            return byId->storageId();
        }
        const QString binary = DefaultAppsResolver::execBinaryName(value);
        if (binary.isEmpty()) {
            continue;
        }
        const auto matches = KApplicationTrader::query([&binary](const KService::Ptr &service) {
            return DefaultAppsResolver::execBinaryName(service->exec()) == binary;
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
    const auto raw = loadMimeAppsDefaults();
    out.defaults = QSet<QString>(raw.cbegin(), raw.cend());
    out.preferred = resolvePreferredRoles();
    return out;
}

namespace DefaultAppsResolver
{
QStringList mimeAppsDefaults(const KConfig &mimeApps)
{
    QSet<QString> result;
    const auto entries = mimeApps.group(QStringLiteral("Default Applications")).entryMap();
    for (const QString &value : entries) {
        // A value may list several .desktop entries separated by ';'.
        const auto ids = value.split(QLatin1Char(';'), Qt::SkipEmptyParts);
        for (const auto &id : ids) {
            const QString trimmed = id.trimmed();
            if (!trimmed.isEmpty()) {
                result.insert(trimmed);
            }
        }
    }
    return QStringList(result.cbegin(), result.cend());
}

QStringList mimeAppsListPaths(const QStringList &configDirs, const QStringList &dataDirs, const QStringList &desktops)
{
    QStringList names;
    for (const QString &desktop : desktops) {
        names.append(desktop.toLower() + QStringLiteral("-mimeapps.list"));
    }
    names.append(QStringLiteral("mimeapps.list"));

    QStringList dirs = configDirs;
    for (const QString &dataDir : dataDirs) {
        dirs.append(dataDir + QStringLiteral("/applications"));
    }
    QStringList paths;
    for (const QString &dir : std::as_const(dirs)) {
        for (const QString &name : std::as_const(names)) {
            paths.append(dir + QLatin1Char('/') + name);
        }
    }
    return paths;
}

QStringList loadMimeAppsDefaults()
{
    // Plasma writes the user's choices to kde-mimeapps.list as well as
    // mimeapps.list, and Flatpak and the distribution ship theirs under the
    // other XDG dirs; a missing file reads as empty.
    const QStringList paths = mimeAppsListPaths(QStandardPaths::standardLocations(QStandardPaths::GenericConfigLocation),
                                                QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation),
                                                qEnvironmentVariable("XDG_CURRENT_DESKTOP").split(QLatin1Char(':'), Qt::SkipEmptyParts));
    QSet<QString> all;
    for (const QString &path : paths) {
        const auto ids = mimeAppsDefaults(KConfig(path, KConfig::SimpleConfig));
        all.unite(QSet<QString>(ids.cbegin(), ids.cend()));
    }
    return QStringList(all.cbegin(), all.cend());
}

QStringList kdeTerminalDefaults(const KConfigGroup &general)
{
    QStringList values;
    // TerminalApplication carries an exec line (legacy); TerminalService the
    // .desktop id (current Plasma 6). The browser default is intentionally NOT
    // read from kdeglobals — it comes from KApplicationTrader (x-scheme-handler),
    // so a stale BrowserApplication can't shadow the real default. Terminals
    // have no mimetype, so kdeglobals is their only override source.
    for (const char *key : {"TerminalApplication", "TerminalService"}) {
        const QString value = general.readEntry(key, QString());
        if (!value.isEmpty()) {
            values.append(value);
        }
    }
    return values;
}

QStringList loadKdeTerminalDefaults()
{
    return kdeTerminalDefaults(KSharedConfig::openConfig(QStringLiteral("kdeglobals"))->group(QStringLiteral("General")));
}

QString execBinaryName(const QString &execLine)
{
    QString token = execLine.trimmed().section(QLatin1Char(' '), 0, 0);
    // Drop surrounding quotes from a quoted exec path before taking the basename.
    if (token.startsWith(QLatin1Char('"')) || token.startsWith(QLatin1Char('\''))) {
        token.remove(0, 1);
    }
    if (token.endsWith(QLatin1Char('"')) || token.endsWith(QLatin1Char('\''))) {
        token.chop(1);
    }
    const int slash = token.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0) {
        token = token.mid(slash + 1);
    }
    return token;
}
}
