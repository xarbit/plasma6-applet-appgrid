/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "launchstatestore.h"

#include <KConfigGroup>
#include <QTimer>

namespace
{
// The same file + group + keys the daemon already persisted these to, so the
// center variant needs no migration: the store just keeps reading them.
const QString kConfigName = QStringLiteral("appgridrc");
const QString kGroup = QStringLiteral("General");
const QString kHiddenKey = QStringLiteral("hiddenApps");
const QString kRecentKey = QStringLiteral("recentApps");
const QString kKnownKey = QStringLiteral("knownApps");
const QString kLaunchCountsKey = QStringLiteral("launchCounts");

// Coalesce bursts of live writes (hide, launch, recents) into one save.
constexpr int kSaveDebounceMs = 500;
}

LaunchStateStore::LaunchStateStore(KSharedConfig::Ptr config, QObject *parent)
    : QObject(parent)
    , m_config(config ? config : KSharedConfig::openConfig(kConfigName))
{
    load();

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(kSaveDebounceMs);
    connect(m_saveTimer, &QTimer::timeout, this, &LaunchStateStore::save);

    // Pick up hides/launches made by another launcher process or applet instance.
    // Our own writes either don't notify this watcher or reload to identical
    // values (reloadFromExternalChange only emits on a real change), so no guard
    // against self-notification is needed.
    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &) {
        if (group.name() == kGroup) {
            reloadFromExternalChange();
        }
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

QStringList LaunchStateStore::knownApps() const
{
    return m_known;
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

void LaunchStateStore::setKnownApps(const QStringList &list)
{
    if (m_known == list) {
        return;
    }
    m_known = list;
    scheduleSave();
    Q_EMIT knownAppsChanged();
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

bool LaunchStateStore::migrateFrom(const QStringList &hidden, const QStringList &recent, const QStringList &known, const QStringList &counts)
{
    KConfigGroup group = m_config->group(kGroup);
    bool migrated = false;
    // Seed a list only when the store currently has none (empty or absent), so
    // the first launcher to migrate wins and a populated store is never clobbered.
    const auto seed = [&](const QString &key, QStringList &current, const QStringList &incoming) {
        if (incoming.isEmpty() || !current.isEmpty()) {
            return;
        }
        group.writeEntry(key, incoming);
        current = incoming;
        migrated = true;
    };
    seed(kHiddenKey, m_hidden, hidden);
    seed(kRecentKey, m_recent, recent);
    seed(kKnownKey, m_known, known);
    if (!counts.isEmpty() && m_launchCounts.isEmpty()) {
        group.writeEntry(kLaunchCountsKey, counts);
        m_launchCounts = countsFromList(counts);
        migrated = true;
    }

    if (migrated) {
        group.sync();
        Q_EMIT hiddenAppsChanged();
        Q_EMIT recentAppsChanged();
        Q_EMIT knownAppsChanged();
        Q_EMIT launchCountsChanged();
    }
    return migrated;
}

void LaunchStateStore::load()
{
    const KConfigGroup group = m_config->group(kGroup);
    m_hidden = group.readEntry(kHiddenKey, QStringList());
    m_recent = group.readEntry(kRecentKey, QStringList());
    m_known = group.readEntry(kKnownKey, QStringList());
    m_launchCounts = countsFromList(group.readEntry(kLaunchCountsKey, QStringList()));
}

void LaunchStateStore::scheduleSave()
{
    m_saveTimer->start();
}

void LaunchStateStore::save()
{
    KConfigGroup group = m_config->group(kGroup);
    group.writeEntry(kHiddenKey, m_hidden);
    group.writeEntry(kRecentKey, m_recent);
    group.writeEntry(kKnownKey, m_known);
    group.writeEntry(kLaunchCountsKey, countsToList(m_launchCounts));
    group.sync();
}

void LaunchStateStore::reloadFromExternalChange()
{
    const QStringList hidden = m_hidden;
    const QStringList recent = m_recent;
    const QStringList known = m_known;
    const QVariantMap counts = m_launchCounts;

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
    if (m_known != known) {
        Q_EMIT knownAppsChanged();
    }
    if (m_launchCounts != counts) {
        Q_EMIT launchCountsChanged();
    }
}

QVariantMap LaunchStateStore::countsFromList(const QStringList &list)
{
    QVariantMap map;
    for (const QString &entry : list) {
        const int sep = entry.lastIndexOf(QLatin1Char('='));
        if (sep <= 0) {
            continue;
        }
        map.insert(entry.left(sep), entry.mid(sep + 1).toInt());
    }
    return map;
}

QStringList LaunchStateStore::countsToList(const QVariantMap &map)
{
    QStringList list;
    list.reserve(map.size());
    for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
        list << it.key() + QLatin1Char('=') + QString::number(it.value().toInt());
    }
    return list;
}
