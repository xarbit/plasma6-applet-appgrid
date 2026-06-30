/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "launchstatestore.h"

#include "favoritesfolderlogic.h"
#include "keyvaluelist.h"

#include <KConfigGroup>
#include <QTimer>

#include <optional>

namespace
{
// The same file + group + keys the daemon already persisted these to, so the
// center variant needs no migration: the store just keeps reading them.
const QString kConfigName = QStringLiteral("appgridrc");
const QString kGroup = QStringLiteral("General");
const QString kHiddenKey = QStringLiteral("hiddenApps");
const QString kRecentKey = QStringLiteral("recentApps");
const QString kLaunchCountsKey = QStringLiteral("launchCounts");
const QString kFoldersKey = QStringLiteral("favoriteFolders");
const QString kLayoutKey = QStringLiteral("favoriteLayout");

// Folder storage. Global folder definitions live in [General] (shown in every
// activity); an activity's local folders + its top-level order live under
// [Folders][<activityId>]. With no activity set (scoping off) everything is in
// [General] — the previous global behaviour.
const QString kFoldersGroup = QStringLiteral("Folders");

// Coalesce bursts of live writes (hide, launch, recents) into one save.
constexpr int kSaveDebounceMs = 500;

using FavoritesFolderLogic::Folder;

// A group's folders, with their global flag forced — the group they load from is
// the authority (the on-disk flag is only a carrier).
QList<Folder> readFolders(const KConfigGroup &group, bool global)
{
    QList<Folder> folders = FavoritesFolderLogic::foldersFromVariant(FavoritesFolderLogic::foldersFromJsonList(group.readEntry(kFoldersKey, QStringList())));
    for (Folder &f : folders) {
        f.global = global;
    }
    return folders;
}

QStringList foldersToJson(const QList<Folder> &folders)
{
    return FavoritesFolderLogic::foldersToJsonList(FavoritesFolderLogic::foldersToVariant(folders));
}
}

LaunchStateStore::LaunchStateStore(const KSharedConfig::Ptr &config, QObject *parent)
    : QObject(parent)
    , m_config(config ? config : KSharedConfig::openConfig(kConfigName))
{
    load();

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(kSaveDebounceMs);
    connect(m_saveTimer, &QTimer::timeout, this, &LaunchStateStore::save);

    // Coalesce the burst of per-group configChanged a single write emits into one
    // reparse — without this, a save touching [General] + a [Folders] group would
    // reparse the file (disk I/O) once per group.
    m_reloadTimer = new QTimer(this);
    m_reloadTimer->setSingleShot(true);
    m_reloadTimer->setInterval(0);
    connect(m_reloadTimer, &QTimer::timeout, this, &LaunchStateStore::reloadFromExternalChange);

    // Pick up changes made by another launcher process or applet instance — both
    // [General] (hides/launches/global folders) and a [Folders][<activity>] group
    // (per-activity folders). appgridrc is ours, so any change is relevant; our
    // own writes reload to identical values (reloadFromExternalChange only emits
    // on a real change), so no self-notification guard is needed.
    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &, const QByteArrayList &) {
        m_reloadTimer->start();
    });
}

QStringList LaunchStateStore::hiddenApps() const
{
    return m_hidden;
}

QStringList LaunchStateStore::recentApps() const
{
    return m_recent;
}

QVariantMap LaunchStateStore::launchCounts() const
{
    return m_launchCounts;
}

void LaunchStateStore::setHiddenApps(const QStringList &list)
{
    if (m_hidden == list) {
        return;
    }
    m_hidden = list;
    scheduleSave();
    Q_EMIT hiddenAppsChanged();
}

void LaunchStateStore::setRecentApps(const QStringList &list)
{
    if (m_recent == list) {
        return;
    }
    m_recent = list;
    scheduleSave();
    Q_EMIT recentAppsChanged();
}

void LaunchStateStore::setLaunchCounts(const QVariantMap &counts)
{
    if (m_launchCounts == counts) {
        return;
    }
    m_launchCounts = counts;
    scheduleSave();
    Q_EMIT launchCountsChanged();
}

QVariantList LaunchStateStore::favoriteFolders() const
{
    return m_favoriteFolders;
}

QStringList LaunchStateStore::favoriteLayout() const
{
    return m_favoriteLayout;
}

void LaunchStateStore::setFavoriteFolders(const QVariantList &folders)
{
    if (m_favoriteFolders == folders) {
        return;
    }
    m_favoriteFolders = folders;
    scheduleSave();
    Q_EMIT favoriteFoldersChanged();
}

void LaunchStateStore::setFavoriteLayout(const QStringList &layout)
{
    if (m_favoriteLayout == layout) {
        return;
    }
    m_favoriteLayout = layout;
    scheduleSave();
    Q_EMIT favoriteLayoutChanged();
}

bool LaunchStateStore::migrateFrom(const QStringList &hidden, const QStringList &recent, const QStringList &counts)
{
    KConfigGroup group = m_config->group(kGroup);
    bool migrated = false;
    // Seed a list only when the store currently has none (empty or absent), so
    // the first launcher to migrate wins and a populated store is never clobbered.
    const auto flags = KConfigBase::Persistent | KConfigBase::Notify;
    const auto seed = [&](const QString &key, QStringList &current, const QStringList &incoming) {
        if (incoming.isEmpty() || !current.isEmpty()) {
            return;
        }
        group.writeEntry(key, incoming, flags);
        current = incoming;
        migrated = true;
    };
    seed(kHiddenKey, m_hidden, hidden);
    seed(kRecentKey, m_recent, recent);
    if (!counts.isEmpty() && m_launchCounts.isEmpty()) {
        group.writeEntry(kLaunchCountsKey, counts, flags);
        m_launchCounts = countsFromList(counts);
        migrated = true;
    }

    if (migrated) {
        group.sync();
        Q_EMIT hiddenAppsChanged();
        Q_EMIT recentAppsChanged();
        Q_EMIT launchCountsChanged();
    }
    return migrated;
}

void LaunchStateStore::load()
{
    const KConfigGroup group = m_config->group(kGroup);
    m_hidden = group.readEntry(kHiddenKey, QStringList());
    m_recent = group.readEntry(kRecentKey, QStringList());
    m_launchCounts = countsFromList(group.readEntry(kLaunchCountsKey, QStringList()));
    loadFolders();
}

void LaunchStateStore::pruneActivities(const QStringList &activityIds)
{
    // Empty means KActivities isn't ready — don't mistake that for "no activities"
    // and wipe every per-activity layout.
    if (activityIds.isEmpty()) {
        return;
    }
    KConfigGroup folders = m_config->group(kFoldersGroup);
    bool removed = false;
    const QStringList subGroups = folders.groupList();
    for (const QString &sub : subGroups) {
        if (!activityIds.contains(sub)) {
            folders.group(sub).deleteGroup();
            removed = true;
        }
    }
    // Delete in memory; let the debounced save flush it, off this signal path.
    if (removed) {
        scheduleSave();
    }
}

void LaunchStateStore::loadFolders()
{
    const KConfigGroup globalGroup = m_config->group(kGroup);
    if (m_activity.isEmpty()) {
        // Scoping off: everything is global, in [General].
        m_favoriteFolders = FavoritesFolderLogic::foldersToVariant(readFolders(globalGroup, false));
        m_favoriteLayout = globalGroup.readEntry(kLayoutKey, QStringList());
        return;
    }
    // Per-activity: global folders ([General]) plus this activity's local folders;
    // the activity owns the top-level order (empty until first edit — reconcile
    // then appends the global folders).
    const KConfigGroup localGroup = m_config->group(kFoldersGroup).group(m_activity);
    m_favoriteFolders = FavoritesFolderLogic::foldersToVariant(readFolders(globalGroup, true) + readFolders(localGroup, false));
    m_favoriteLayout = localGroup.readEntry(kLayoutKey, QStringList());
}

void LaunchStateStore::saveFolders()
{
    const auto flags = KConfigBase::Persistent | KConfigBase::Notify;
    KConfigGroup globalGroup = m_config->group(kGroup);
    const QList<Folder> all = FavoritesFolderLogic::foldersFromVariant(m_favoriteFolders);
    if (m_activity.isEmpty()) {
        globalGroup.writeEntry(kFoldersKey, foldersToJson(all), flags);
        globalGroup.writeEntry(kLayoutKey, m_favoriteLayout, flags);
        return;
    }
    // Split by the global flag: global defs to [General], local defs + the
    // activity's order to [Folders][<activity>].
    QList<Folder> globalDefs;
    QList<Folder> localDefs;
    for (const Folder &f : all) {
        (f.global ? globalDefs : localDefs).append(f);
    }
    globalGroup.writeEntry(kFoldersKey, foldersToJson(globalDefs), flags);
    KConfigGroup localGroup = m_config->group(kFoldersGroup).group(m_activity);
    localGroup.writeEntry(kFoldersKey, foldersToJson(localDefs), flags);
    localGroup.writeEntry(kLayoutKey, m_favoriteLayout, flags);
}

void LaunchStateStore::setActivity(const QString &activityId)
{
    if (m_activity == activityId) {
        return;
    }
    // Flush the outgoing activity's pending edits before the in-memory layout is
    // replaced — m_activity still points at it, so they save to the right group.
    if (m_saveTimer->isActive()) {
        m_saveTimer->stop();
        save();
    }
    m_activity = activityId;
    const QVariantList prevFolders = m_favoriteFolders;
    const QStringList prevLayout = m_favoriteLayout;
    loadFolders();
    if (m_favoriteFolders != prevFolders) {
        Q_EMIT favoriteFoldersChanged();
    }
    if (m_favoriteLayout != prevLayout) {
        Q_EMIT favoriteLayoutChanged();
    }
}

void LaunchStateStore::scheduleSave()
{
    m_saveTimer->start();
}

void LaunchStateStore::save()
{
    // Notify: emit the D-Bus change signal on sync so another launcher process's
    // KConfigWatcher fires and re-reads — without it the other variant only sees
    // the change on its next restart.
    const auto flags = KConfigBase::Persistent | KConfigBase::Notify;
    KConfigGroup group = m_config->group(kGroup);
    group.writeEntry(kHiddenKey, m_hidden, flags);
    group.writeEntry(kRecentKey, m_recent, flags);
    group.writeEntry(kLaunchCountsKey, countsToList(m_launchCounts), flags);
    saveFolders();
    group.sync();
}

void LaunchStateStore::reloadFromExternalChange()
{
    // Flush our own pending edits first: load() below overwrites every member
    // from disk, so without this an external change landing mid-debounce would
    // drop a local hide/reorder that hadn't been written yet. save()'s sync()
    // re-reads and merges the other process's groups, so we keep theirs too.
    if (m_saveTimer->isActive()) {
        m_saveTimer->stop();
        save();
    }

    const QStringList hidden = m_hidden;
    const QStringList recent = m_recent;
    const QVariantMap counts = m_launchCounts;
    const QVariantList folders = m_favoriteFolders;
    const QStringList layout = m_favoriteLayout;

    // openConfig() shares one in-memory copy per file; reparse so the read below
    // sees the on-disk change the watcher just announced.
    m_config->reparseConfiguration();
    load();

    if (m_hidden != hidden) {
        Q_EMIT hiddenAppsChanged();
    }
    if (m_recent != recent) {
        Q_EMIT recentAppsChanged();
    }
    if (m_launchCounts != counts) {
        Q_EMIT launchCountsChanged();
    }
    if (m_favoriteFolders != folders) {
        Q_EMIT favoriteFoldersChanged();
    }
    if (m_favoriteLayout != layout) {
        Q_EMIT favoriteLayoutChanged();
    }
}

QVariantMap LaunchStateStore::countsFromList(const QStringList &list)
{
    return KeyValueList::fromList<QVariantMap>(list, [](const QString &value) {
        return std::optional<int>(value.toInt());
    });
}

QStringList LaunchStateStore::countsToList(const QVariantMap &map)
{
    return KeyValueList::toList(map, [](const QVariant &value) {
        return QString::number(value.toInt());
    });
}
