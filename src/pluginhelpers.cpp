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

#include <utility>

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
