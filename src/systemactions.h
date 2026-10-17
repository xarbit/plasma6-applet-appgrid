/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief The launcher's actions on the rest of the system.
 *
 * Commands from the prefix modes (in a terminal or detached), dropping a
 * launcher on the desktop, managing an app in Discover, listing a directory
 * for the file prefix, and the system info for bug reports. Stateless; the
 * controller exposes one instance to QML.
 */
class SystemActions : public QObject
{
    Q_OBJECT

public:
    explicit SystemActions(QObject *parent = nullptr);

    /** Run @p command in the user's terminal emulator with @p shell (one of
     *  /etc/shells, else /bin/sh); the terminal stays open afterwards. */
    Q_INVOKABLE void runInTerminal(const QString &command, const QString &shell = QString());
    /** Run @p command with @p shell, without a terminal. */
    Q_INVOKABLE void runCommand(const QString &command, const QString &shell = QString());
    /** The installed shells listed in /etc/shells. */
    [[nodiscard]] Q_INVOKABLE QStringList availableShells() const;

    /** Drop @p desktopFile (an absolute .desktop path) on the desktop, as
     *  Folder View does for an app drag. */
    Q_INVOKABLE void addToDesktop(const QString &desktopFile);
    /** True if a Folder View desktop exists to show a dropped launcher. */
    [[nodiscard]] Q_INVOKABLE bool canAddToDesktop() const;

    /** True if KDE Discover is installed. */
    [[nodiscard]] Q_INVOKABLE bool isDiscoverAvailable() const;
    /** True if a Discover backend owns the installed copy of @p storageId. */
    [[nodiscard]] Q_INVOKABLE bool canManageInDiscover(const QString &storageId) const;
    /** Open Discover on the app @p storageId. */
    Q_INVOKABLE void openInDiscover(const QString &storageId);

    /** The entries of the directory @p path: {name, path, isDir, icon}. */
    [[nodiscard]] Q_INVOKABLE QVariantList listDirectory(const QString &path) const;

    /** System and environment info for bug reports. @p variant labels the
     *  form factor (Center, Panel or Standalone). */
    [[nodiscard]] Q_INVOKABLE QVariantMap systemInfo(const QString &variant) const;
};
