/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QString>

/**
 * The fields a launcher row shows for an id (an app, a jump-list action, a
 * document), resolved through AppResolver once per id and kept until
 * clear() — call it when the installed apps change (KSycoca).
 */
class AppFieldsCache
{
public:
    struct Fields {
        QString name;
        QString icon;
        QString genericName;
        QString comment;
        QString desktopFile;
        QString installSource;
    };

    /** The fields of @p id; empty ones when it resolves to nothing. */
    [[nodiscard]] Fields fields(const QString &id) const;
    void clear();

private:
    mutable QHash<QString, Fields> m_fields;
};
