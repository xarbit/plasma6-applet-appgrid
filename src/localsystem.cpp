/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "localsystem.h"

#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QVariantMap>

namespace
{
// Cap the prefix-mode file browser listing so a huge directory can't stall the
// completion popup; the user narrows with the filter rather than scrolling.
constexpr int kMaxDirectoryEntries = 200;
}

namespace LocalSystem
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
}
