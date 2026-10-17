/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KConfigWatcher>

#include <QObject>
#include <QSet>
#include <QString>

/**
 * Keeps the user's default applications current: the mime defaults
 * (mimeapps.list) and the role defaults (browser, mail, file manager,
 * terminal), as resolved by DefaultAppsResolver.
 *
 * Resolving runs full KApplicationTrader scans, so it happens once shortly
 * after construction (not in the constructor, which inside plasmashell would
 * delay the shell's startup) and then only when KSycoca or kdeglobals'
 * [General] group changes — never on the launcher-open path (#200).
 */
class DefaultAppsProvider : public QObject
{
    Q_OBJECT

public:
    explicit DefaultAppsProvider(QObject *parent = nullptr);

    /** Storage ids of every mimeapps.list default. */
    [[nodiscard]] QSet<QString> defaults() const
    {
        return m_defaults;
    }
    /** Storage ids of the role defaults (browser, mail, file manager, terminal). */
    [[nodiscard]] QSet<QString> preferred() const
    {
        return m_preferred;
    }

    /** Resolve again now; emits changed() when either set differs. */
    void reload();

Q_SIGNALS:
    void changed();

private:
    QSet<QString> m_defaults;
    QSet<QString> m_preferred;
    // kdeglobals' terminal override is the one default-app input KSycoca
    // doesn't notify about.
    KConfigWatcher::Ptr m_kdeglobalsWatcher;
};
