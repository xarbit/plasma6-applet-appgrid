/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QList>
#include <QMimeDatabase>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QVariantMap>

namespace
{
// Cap the prefix-mode file browser listing so a huge directory can't stall the
// completion popup; the user narrows with the filter rather than scrolling.
constexpr int kMaxDirectoryEntries = 200;
}

namespace PluginHelpers
{
QStringList parseShells(const QString &contents)
{
    QStringList shells;
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto &raw : lines) {
        const QString line = raw.trimmed();
        if (!line.isEmpty() && !line.startsWith(QLatin1Char('#'))) {
            shells.append(line);
        }
    }
    return shells;
}

QString parseOsPrettyName(const QString &contents)
{
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto &raw : lines) {
        // Trim so a stray CR from CRLF endings doesn't break the quote-strip
        // below (PRETTY_NAME="…\r" wouldn't endsWith('"') and the value
        // would leak through with a trailing carriage return).
        const QString line = raw.trimmed();
        if (line.startsWith(QLatin1String("PRETTY_NAME="))) {
            QString val = line.mid(12);
            if (val.startsWith(QLatin1Char('"')) && val.endsWith(QLatin1Char('"'))) {
                val = val.mid(1, val.length() - 2);
            }
            return val;
        }
    }
    return {};
}

QString expandTilde(const QString &path)
{
    if (path.startsWith(QLatin1Char('~'))) {
        return QDir::homePath() + path.mid(1);
    }
    return path;
}

QVariantList listDirectoryAt(const QString &path)
{
    const QString expanded = expandTilde(path);

    // Split into directory + filter for partial paths.
    QDir dir(expanded);
    QString filter;
    if (!dir.exists()) {
        QFileInfo fi(expanded);
        dir = QDir(fi.path());
        filter = fi.fileName();
        if (!dir.exists()) {
            return {};
        }
    }

    QVariantList result;
    result.reserve(kMaxDirectoryEntries);
    QMimeDatabase mimeDb;

    dir.setFilter(QDir::AllEntries | QDir::NoDot);
    dir.setSorting(QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);

    const auto entries = dir.entryInfoList();
    for (const auto &entry : entries) {
        if (!filter.isEmpty() && !entry.fileName().contains(filter, Qt::CaseInsensitive)) {
            continue;
        }

        QVariantMap item;
        item[QStringLiteral("name")] = entry.fileName();
        item[QStringLiteral("path")] = entry.absoluteFilePath();
        item[QStringLiteral("isDir")] = entry.isDir();

        if (entry.isDir()) {
            item[QStringLiteral("icon")] = QStringLiteral("folder");
        } else {
            const auto mime = mimeDb.mimeTypeForFile(entry);
            item[QStringLiteral("icon")] = mime.iconName();
        }

        result.append(item);
        if (result.size() >= kMaxDirectoryEntries) {
            break;
        }
    }
    return result;
}

namespace
{
// Invoke @p fn(key, value) for every "key=value" line inside @p sectionHeader
// (e.g. "[Default Applications]") of an INI-style file's @p contents. Section
// headers, comments and keyless lines are skipped. Shared by the mimeapps and
// kdeglobals parsers so the section/comment handling lives in one place.
template<typename Fn>
void forEachIniEntry(const QString &contents, const QLatin1String &sectionHeader, Fn &&fn)
{
    bool inSection = false;
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto &raw : lines) {
        const QString line = raw.trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inSection = (line == sectionHeader);
            continue;
        }
        if (!inSection || line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0) { // no '=' or empty key
            continue;
        }
        fn(line.left(eq).trimmed(), line.mid(eq + 1).trimmed());
    }
}

// The mimeapps.list files in XDG precedence (user first, then system).
QStringList mimeAppsListPaths()
{
    return {
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/mimeapps.list"),
        QStringLiteral("/usr/share/applications/mimeapps.list"),
    };
}

// Run @p parser over every mimeapps.list and merge the de-duplicated result.
// The path list and read loop live here rather than in each caller.
template<typename Parser>
QStringList mergeMimeAppsLists(Parser &&parser)
{
    QSet<QString> all;
    for (const auto &path : mimeAppsListPaths()) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        const auto items = parser(QString::fromUtf8(f.readAll()));
        for (const auto &item : items) {
            all.insert(item);
        }
    }
    return QStringList(all.cbegin(), all.cend());
}
}

QStringList parseMimeAppsDefaults(const QString &contents)
{
    QSet<QString> result;
    forEachIniEntry(contents, QLatin1String("[Default Applications]"), [&result](const QString &, const QString &value) {
        // A value may list several .desktop entries separated by ';'.
        const auto ids = value.split(QLatin1Char(';'), Qt::SkipEmptyParts);
        for (const auto &id : ids) {
            const QString trimmed = id.trimmed();
            if (!trimmed.isEmpty()) {
                result.insert(trimmed);
            }
        }
    });
    return QStringList(result.cbegin(), result.cend());
}

QStringList loadMimeAppsDefaults()
{
    return mergeMimeAppsLists(parseMimeAppsDefaults);
}

QString desktopPathFromRunnerUrls(const QVariant &urlsData)
{
    const auto urls = urlsData.value<QList<QUrl>>();
    for (const auto &url : urls) {
        const auto path = url.toLocalFile();
        if (path.endsWith(QLatin1String(".desktop"))) {
            return path;
        }
    }
    return {};
}

QString runnerStorageId(const QVariant &urlsData)
{
    const QString path = desktopPathFromRunnerUrls(urlsData);
    return path.isEmpty() ? QString() : QFileInfo(path).fileName();
}

QStringList parseKdeTerminalDefaults(const QString &contents)
{
    QStringList values;
    // TerminalApplication carries an exec line (legacy); TerminalService the
    // .desktop id (current Plasma 6). The browser default is intentionally NOT
    // read from kdeglobals — it comes from KApplicationTrader (x-scheme-handler),
    // so a stale BrowserApplication can't shadow the real default. Terminals
    // have no mimetype, so kdeglobals is their only override source.
    forEachIniEntry(contents, QLatin1String("[General]"), [&values](const QString &key, const QString &value) {
        if ((key == QLatin1String("TerminalApplication") || key == QLatin1String("TerminalService")) && !value.isEmpty()) {
            values.append(value);
        }
    });
    return values;
}

QStringList loadKdeTerminalDefaults()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kdeglobals");
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return parseKdeTerminalDefaults(QString::fromUtf8(f.readAll()));
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

QStringList readRunnerFavorites(const QExplicitlySharedDataPointer<KSharedConfig> &config)
{
    if (!config) {
        return {};
    }
    // krunnerrc shape: [Plugins][Favorites] plugins=id1,id2,…
    return config->group(QStringLiteral("Plugins")).group(QStringLiteral("Favorites")).readEntry("plugins", QStringList());
}

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
