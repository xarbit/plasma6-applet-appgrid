/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>
#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QTimer;

/**
 * @brief The single, shared persistence for per-user launch state.
 *
 * Hidden apps, the recents list, the known-apps set (new-app badge) and the
 * per-app launch counts are user-global data — "which apps I've hidden", not a
 * property of one panel icon. Historically each surface persisted them in its
 * own config (every panel applet in its own desktop-appletsrc entry, the daemon
 * in appgridrc), so the panel and center variants drifted apart.
 *
 * This store keeps them in one file — appgridrc, the [General] group, the same
 * keys the daemon already wrote — so every variant and the daemon read and write
 * the same list. A KConfigWatcher re-reads the file when another process or
 * applet instance changes it, so a hide in one launcher shows up live in the
 * rest. Writes are coalesced into a debounced save.
 *
 * Favourites are NOT here: they already live in the system-wide KActivities
 * stats database (KAStatsFavoritesModel), which is global by construction.
 */
class LaunchStateStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList hiddenApps READ hiddenApps WRITE setHiddenApps NOTIFY hiddenAppsChanged)
    Q_PROPERTY(QStringList recentApps READ recentApps WRITE setRecentApps NOTIFY recentAppsChanged)
    Q_PROPERTY(QStringList knownApps READ knownApps WRITE setKnownApps NOTIFY knownAppsChanged)
    Q_PROPERTY(QVariantMap launchCounts READ launchCounts WRITE setLaunchCounts NOTIFY launchCountsChanged)
    // Favourites folders (issue #18): an AppGrid-only grouping over the shared
    // KAStats favourites. The favourites themselves stay in KAStats; only the
    // folder definitions + top-level order live here, shared across variants.
    Q_PROPERTY(QVariantList favoriteFolders READ favoriteFolders WRITE setFavoriteFolders NOTIFY favoriteFoldersChanged)
    Q_PROPERTY(QStringList favoriteLayout READ favoriteLayout WRITE setFavoriteLayout NOTIFY favoriteLayoutChanged)

public:
    /** @p config defaults to appgridrc; injectable so tests can point at a
     *  scratch file. */
    explicit LaunchStateStore(const KSharedConfig::Ptr &config = {}, QObject *parent = nullptr);

    [[nodiscard]] QStringList hiddenApps() const;
    [[nodiscard]] QStringList recentApps() const;
    [[nodiscard]] QStringList knownApps() const;
    [[nodiscard]] QVariantMap launchCounts() const;
    [[nodiscard]] QVariantList favoriteFolders() const;
    [[nodiscard]] QStringList favoriteLayout() const;

    void setHiddenApps(const QStringList &list);
    void setRecentApps(const QStringList &list);
    void setKnownApps(const QStringList &list);
    void setLaunchCounts(const QVariantMap &counts);
    void setFavoriteFolders(const QVariantList &folders);
    void setFavoriteLayout(const QStringList &layout);

    /** Scope folders/layout to @p activityId (per-activity folders). Flushes the
     *  outgoing activity's pending edits, then loads the new activity's layout,
     *  falling back to the shared legacy layout until that activity diverges. The
     *  id is fed from the controller's KActivities consumer, so this class stays
     *  KConfig-only. */
    void setActivity(const QString &activityId);

    /** Seed any empty key from a variant's old per-applet config (panel upgrade).
     *  @p counts is the on-disk "storageId=count" StringList. Writes only the
     *  keys still absent from the file, so the first launcher to migrate wins and
     *  later ones don't clobber the shared list. Returns true if anything moved. */
    bool migrateFrom(const QStringList &hidden, const QStringList &recent, const QStringList &known, const QStringList &counts);

Q_SIGNALS:
    void hiddenAppsChanged();
    void recentAppsChanged();
    void knownAppsChanged();
    void launchCountsChanged();
    void favoriteFoldersChanged();
    void favoriteLayoutChanged();

private:
    void load();
    // Read folders + layout for the current activity, with copy-on-write fallback
    // to the shared legacy layout. Split out so setActivity() reuses it.
    void loadFolders();
    void scheduleSave();
    void save();
    // Re-read after an external change and emit only the keys that moved.
    void reloadFromExternalChange();

    // launchCounts persists as a "storageId=count" StringList (the on-disk form
    // the daemon already used); convert at the file boundary.
    [[nodiscard]] static QVariantMap countsFromList(const QStringList &list);
    [[nodiscard]] static QStringList countsToList(const QVariantMap &map);

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    QTimer *m_saveTimer = nullptr;

    QStringList m_hidden;
    QStringList m_recent;
    QStringList m_known;
    QVariantMap m_launchCounts;
    QVariantList m_favoriteFolders;
    QStringList m_favoriteLayout;
    // Current activity id; folders/layout are scoped to it. Empty = the shared
    // legacy layout (the only state single-activity users ever see).
    QString m_activity;
};
