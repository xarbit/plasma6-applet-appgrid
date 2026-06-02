/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "pluginhelpers.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QSet>
#include <QStandardPaths>
#include <QVariantMap>

namespace PluginHelpers
{
QStringList parseShells(const QString &contents)
{
    QStringList shells;
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto &raw : lines) {
        const QString line = raw.trimmed();
        if (!line.isEmpty() && !line.startsWith(QLatin1Char('#')))
            shells.append(line);
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
            if (val.startsWith(QLatin1Char('"')) && val.endsWith(QLatin1Char('"')))
                val = val.mid(1, val.length() - 2);
            return val;
        }
    }
    return {};
}

QString expandTilde(const QString &path)
{
    if (path.startsWith(QLatin1Char('~')))
        return QDir::homePath() + path.mid(1);
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
        if (!dir.exists())
            return {};
    }

    QVariantList result;
    QMimeDatabase mimeDb;

    dir.setFilter(QDir::AllEntries | QDir::NoDot);
    dir.setSorting(QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);

    const auto entries = dir.entryInfoList();
    for (const auto &entry : entries) {
        if (!filter.isEmpty() && !entry.fileName().contains(filter, Qt::CaseInsensitive))
            continue;

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
        if (result.size() >= 200)
            break;
    }
    return result;
}

QStringList parseMimeAppsDefaults(const QString &contents)
{
    QSet<QString> result;
    bool inDefaults = false;
    const auto lines = contents.split(QLatin1Char('\n'));
    for (const auto &raw : lines) {
        const QString line = raw.trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inDefaults = (line == QLatin1String("[Default Applications]"));
            continue;
        }
        if (!inDefaults || line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq < 0)
            continue;
        // A value may list several .desktop entries separated by ';'.
        const auto values = line.mid(eq + 1).split(QLatin1Char(';'), Qt::SkipEmptyParts);
        for (const auto &v : values) {
            const QString trimmed = v.trimmed();
            if (!trimmed.isEmpty())
                result.insert(trimmed);
        }
    }
    return QStringList(result.cbegin(), result.cend());
}

QStringList loadMimeAppsDefaults()
{
    QSet<QString> all;
    const QStringList paths = {
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + QStringLiteral("/mimeapps.list"),
        QStringLiteral("/usr/share/applications/mimeapps.list"),
    };
    for (const auto &path : paths) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const auto ids = parseMimeAppsDefaults(QString::fromUtf8(f.readAll()));
        for (const auto &id : ids)
            all.insert(id);
    }
    return QStringList(all.cbegin(), all.cend());
}
}
