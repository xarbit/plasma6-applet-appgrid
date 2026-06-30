/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "newappstracker.h"

#include "keyvaluelist.h"
#include "usedappsprovider.h"

#include <KConfigGroup>

#include <optional>

namespace
{
// How many days an app counts as newly installed. Matches Kickoff's
// AppEntry::s_newlyInstalledDays.
constexpr int kNewAppDays = 3;

constexpr QLatin1String kGroup{"NewApps"};
constexpr QLatin1String kInstalledKey{"installedApps"};
constexpr QLatin1String kFirstSeenKey{"firstSeen"};

// An app is "newly installed" while its first-seen date is valid and inside the
// window; the same predicate gates both the stored set and the badge set.
bool withinWindow(const QDate &firstSeen, const QDate &today)
{
    return firstSeen.isValid() && firstSeen.daysTo(today) < kNewAppDays;
}

// firstSeen persists as a "storageId=yyyy-MM-dd" StringList, mirroring the
// launch-count on-disk form; convert at the file boundary.
QHash<QString, QDate> firstSeenFromList(const QStringList &list)
{
    return KeyValueList::fromList<QHash<QString, QDate>>(list, [](const QString &value) -> std::optional<QDate> {
        const QDate date = QDate::fromString(value, Qt::ISODate);
        return date.isValid() ? std::optional(date) : std::nullopt;
    });
}

QStringList firstSeenToList(const QHash<QString, QDate> &map)
{
    QStringList list = KeyValueList::toList(map, [](const QDate &date) {
        return date.toString(Qt::ISODate);
    });
    list.sort(); // stable on-disk order, so an unchanged set never rewrites
    return list;
}
}

NewAppsTracker::NewAppsTracker(UsedAppsProvider *usedApps, const KSharedConfig::Ptr &config, QObject *parent)
    : QObject(parent)
    , m_usedApps(usedApps)
    // Own state file, NOT the shared appgridrc: syncing it must never trip the
    // launch-state KConfigWatcher (that reload would clobber in-memory favorites
    // / recents). Kickoff keeps its new-app state in a separate config too.
    , m_config(config ? config : KSharedConfig::openConfig(QStringLiteral("appgridstaterc")))
{
    m_firstSeen = firstSeenFromList(m_config->group(kGroup).readEntry(kFirstSeenKey, QStringList()));
    if (m_usedApps) {
        connect(m_usedApps, &UsedAppsProvider::usedAppsChanged, this, &NewAppsTracker::recompute);
    }
    recompute();
}

void NewAppsTracker::refresh(const QStringList &installedIds)
{
    // The app model loads asynchronously; an empty list means "not loaded yet",
    // never a real install state. Refreshing on it would wipe the baseline and
    // then reseed from the full list, so a genuinely new app would never flag.
    if (installedIds.isEmpty()) {
        return;
    }

    KConfigGroup group = m_config->group(kGroup);
    const QStringList storedList = group.readEntry(kInstalledKey, QStringList());
    const QSet<QString> stored(storedList.cbegin(), storedList.cend());
    const QDate today = QDate::currentDate();

    QHash<QString, QDate> next;
    next.reserve(installedIds.size());
    for (const QString &id : installedIds) {
        QDate firstSeen;
        if (stored.isEmpty() || stored.contains(id)) {
            // Baseline seed (empty store) or an already-known app: keep its date,
            // but drop it once the window has lapsed so firstSeen stays small.
            firstSeen = m_firstSeen.value(id);
            if (!withinWindow(firstSeen, today)) {
                firstSeen = QDate();
            }
        } else {
            // Absent from a non-empty baseline → genuinely newly installed.
            firstSeen = today;
        }
        if (firstSeen.isValid()) {
            next.insert(id, firstSeen);
        }
    }

    // ponytail: a reinstall inside the window re-flags as new (no LastSeen grace
    // like Kickoff's). Rare and harmless; add the grace only if it bites.
    if (storedList != installedIds) {
        group.writeEntry(kInstalledKey, installedIds);
    }
    const QStringList nextList = firstSeenToList(next);
    if (group.readEntry(kFirstSeenKey, QStringList()) != nextList) {
        group.writeEntry(kFirstSeenKey, nextList);
    }
    if (group.config()->isDirty()) {
        group.sync();
    }

    m_firstSeen = next;
    recompute();
}

void NewAppsTracker::recompute()
{
    const QDate today = QDate::currentDate();
    QSet<QString> next;
    for (auto it = m_firstSeen.cbegin(); it != m_firstSeen.cend(); ++it) {
        if (!withinWindow(it.value(), today)) {
            continue; // window lapsed
        }
        if (m_usedApps && m_usedApps->isUsed(it.key())) {
            continue; // already launched → no longer new (Kickoff's score clear)
        }
        next.insert(it.key());
    }
    if (next != m_new) {
        m_new = next;
        Q_EMIT newAppsChanged();
    }
}
