/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appmodel.h"

#include <KService>
#include <KServiceGroup>
#include <KSycoca>

#include <KIO/ApplicationLauncherJob>
#include <KJob>

#include <QCollator>
#include <algorithm>

// Map freedesktop categories to user-friendly groups
static const QHash<QString, QString> &categoryMap()
{
    static const QHash<QString, QString> map = {
        // Utilities
        {QStringLiteral("Utility"), QStringLiteral("Utilities")},
        {QStringLiteral("Accessibility"), QStringLiteral("Utilities")},
        {QStringLiteral("Core"), QStringLiteral("Utilities")},
        {QStringLiteral("Legacy"), QStringLiteral("Utilities")},
        {QStringLiteral("TextEditor"), QStringLiteral("Utilities")},
        {QStringLiteral("Archiving"), QStringLiteral("Utilities")},
        {QStringLiteral("Compression"), QStringLiteral("Utilities")},
        {QStringLiteral("FileManager"), QStringLiteral("Utilities")},
        {QStringLiteral("TerminalEmulator"), QStringLiteral("Utilities")},
        {QStringLiteral("FileTools"), QStringLiteral("Utilities")},
        {QStringLiteral("Filesystem"), QStringLiteral("Utilities")},
        // Development
        {QStringLiteral("Development"), QStringLiteral("Development")},
        {QStringLiteral("IDE"), QStringLiteral("Development")},
        {QStringLiteral("Debugger"), QStringLiteral("Development")},
        {QStringLiteral("RevisionControl"), QStringLiteral("Development")},
        {QStringLiteral("WebDevelopment"), QStringLiteral("Development")},
        {QStringLiteral("Building"), QStringLiteral("Development")},
        // Graphics
        {QStringLiteral("Graphics"), QStringLiteral("Graphics")},
        {QStringLiteral("2DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("3DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("RasterGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("VectorGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("Photography"), QStringLiteral("Graphics")},
        {QStringLiteral("ImageProcessing"), QStringLiteral("Graphics")},
        {QStringLiteral("Scanning"), QStringLiteral("Graphics")},
        // Internet
        {QStringLiteral("Network"), QStringLiteral("Internet")},
        {QStringLiteral("WebBrowser"), QStringLiteral("Internet")},
        {QStringLiteral("Email"), QStringLiteral("Internet")},
        {QStringLiteral("Chat"), QStringLiteral("Internet")},
        {QStringLiteral("InstantMessaging"), QStringLiteral("Internet")},
        {QStringLiteral("IRCClient"), QStringLiteral("Internet")},
        {QStringLiteral("FileTransfer"), QStringLiteral("Internet")},
        {QStringLiteral("P2P"), QStringLiteral("Internet")},
        {QStringLiteral("RemoteAccess"), QStringLiteral("Internet")},
        {QStringLiteral("News"), QStringLiteral("Internet")},
        // Multimedia
        {QStringLiteral("AudioVideo"), QStringLiteral("Multimedia")},
        {QStringLiteral("Audio"), QStringLiteral("Multimedia")},
        {QStringLiteral("Video"), QStringLiteral("Multimedia")},
        {QStringLiteral("Music"), QStringLiteral("Multimedia")},
        {QStringLiteral("Player"), QStringLiteral("Multimedia")},
        {QStringLiteral("Recorder"), QStringLiteral("Multimedia")},
        {QStringLiteral("Midi"), QStringLiteral("Multimedia")},
        {QStringLiteral("Mixer"), QStringLiteral("Multimedia")},
        {QStringLiteral("Sequencer"), QStringLiteral("Multimedia")},
        // Office
        {QStringLiteral("Office"), QStringLiteral("Office")},
        {QStringLiteral("Calendar"), QStringLiteral("Office")},
        {QStringLiteral("ContactManagement"), QStringLiteral("Office")},
        {QStringLiteral("Database"), QStringLiteral("Office")},
        {QStringLiteral("Dictionary"), QStringLiteral("Office")},
        {QStringLiteral("Finance"), QStringLiteral("Office")},
        {QStringLiteral("Presentation"), QStringLiteral("Office")},
        {QStringLiteral("ProjectManagement"), QStringLiteral("Office")},
        {QStringLiteral("Spreadsheet"), QStringLiteral("Office")},
        {QStringLiteral("WordProcessor"), QStringLiteral("Office")},
        // Games
        {QStringLiteral("Game"), QStringLiteral("Games")},
        {QStringLiteral("ActionGame"), QStringLiteral("Games")},
        {QStringLiteral("AdventureGame"), QStringLiteral("Games")},
        {QStringLiteral("ArcadeGame"), QStringLiteral("Games")},
        {QStringLiteral("BoardGame"), QStringLiteral("Games")},
        {QStringLiteral("BlocksGame"), QStringLiteral("Games")},
        {QStringLiteral("CardGame"), QStringLiteral("Games")},
        {QStringLiteral("LogicGame"), QStringLiteral("Games")},
        {QStringLiteral("Simulation"), QStringLiteral("Games")},
        {QStringLiteral("SportsGame"), QStringLiteral("Games")},
        {QStringLiteral("StrategyGame"), QStringLiteral("Games")},
        // Education & Science
        {QStringLiteral("Education"), QStringLiteral("Education")},
        {QStringLiteral("Science"), QStringLiteral("Education")},
        {QStringLiteral("Math"), QStringLiteral("Education")},
        {QStringLiteral("Astronomy"), QStringLiteral("Education")},
        {QStringLiteral("Chemistry"), QStringLiteral("Education")},
        {QStringLiteral("Geography"), QStringLiteral("Education")},
        {QStringLiteral("Languages"), QStringLiteral("Education")},
        // System
        {QStringLiteral("System"), QStringLiteral("System")},
        {QStringLiteral("Settings"), QStringLiteral("System")},
        {QStringLiteral("Monitor"), QStringLiteral("System")},
        {QStringLiteral("Security"), QStringLiteral("System")},
        {QStringLiteral("PackageManager"), QStringLiteral("System")},
        {QStringLiteral("HardwareSettings"), QStringLiteral("System")},
        {QStringLiteral("Printing"), QStringLiteral("System")},
    };
    return map;
}

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    loadApplications();
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &AppModel::reload);
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_apps.size();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_apps.size())
        return {};

    const auto &app = m_apps[index.row()];
    switch (role) {
    case NameRole:
        return app.name;
    case IconRole:
        return app.icon;
    case DesktopFileRole:
        return app.desktopFile;
    case CategoryRole:
        return app.category;
    case GenericNameRole:
        return app.genericName;
    case StorageIdRole:
        return app.storageId;
    }
    return {};
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {IconRole, "iconName"},
        {DesktopFileRole, "desktopFile"},
        {CategoryRole, "category"},
        {GenericNameRole, "genericName"},
        {StorageIdRole, "storageId"},
    };
}

QString AppModel::mapCategory(const QStringList &categories) const
{
    const auto &map = categoryMap();
    for (const auto &cat : categories) {
        auto it = map.find(cat);
        if (it != map.end())
            return it.value();
    }
    return QStringLiteral("Other");
}

void AppModel::loadApplications()
{
    QSet<QString> seen;
    QSet<QString> categorySet;

    // Traverse the XDG menu hierarchy via KServiceGroup.
    // This respects .menu exclude rules and shows only apps that
    // belong to the desktop menu, like Kicker/Kickoff do.
    std::function<void(KServiceGroup::Ptr)> walkGroup;
    walkGroup = [&](KServiceGroup::Ptr group) {
        if (!group || !group->isValid())
            return;

        const auto entries = group->entries(true /* sorted */,
                                            true /* excludeNoDisplay */,
                                            false /* allowSeparators */,
                                            true /* sortByGenericName */);

        for (const auto &entry : entries) {
            if (entry->isType(KST_KServiceGroup)) {
                walkGroup(KServiceGroup::Ptr(static_cast<KServiceGroup *>(entry.data())));
                continue;
            }

            if (!entry->isType(KST_KService))
                continue;

            auto service = KService::Ptr(static_cast<KService *>(entry.data()));

            if (!service->isApplication())
                continue;
            if (service->noDisplay() || service->exec().isEmpty())
                continue;

            const QString storageId = service->storageId();
            if (storageId.isEmpty() || seen.contains(storageId))
                continue;
            seen.insert(storageId);

            const QString name = service->name();
            if (name.isEmpty())
                continue;

            AppEntry appEntry;
            appEntry.name = name;
            appEntry.icon = service->icon();
            appEntry.desktopFile = service->entryPath();
            appEntry.genericName = service->genericName();
            appEntry.exec = service->exec();
            appEntry.storageId = storageId;
            appEntry.category = mapCategory(service->categories());

            categorySet.insert(appEntry.category);
            m_apps.append(appEntry);
        }
    };

    walkGroup(KServiceGroup::root());

    // Sort alphabetically
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(m_apps.begin(), m_apps.end(), [&collator](const AppEntry &a, const AppEntry &b) {
        return collator.compare(a.name, b.name) < 0;
    });

    m_categories = categorySet.values();
    m_categories.sort();
}

void AppModel::launch(int index)
{
    if (index < 0 || index >= m_apps.size())
        return;

    const auto &app = m_apps[index];
    auto service = KService::serviceByDesktopPath(app.desktopFile);
    if (!service)
        service = KService::serviceByDesktopName(app.desktopFile);
    if (!service)
        return;

    auto *job = new KIO::ApplicationLauncherJob(service);
    job->setAutoDelete(true);
    connect(job, &KJob::finished, this, [](KJob *j) {
        if (j->error())
            qWarning() << "AppGrid: failed to launch application:" << j->errorString();
    });
    job->start();
}

QStringList AppModel::categories() const
{
    return m_categories;
}

void AppModel::reload()
{
    beginResetModel();
    m_apps.clear();
    m_categories.clear();
    loadApplications();
    endResetModel();
}

// --- AppFilterModel ---

AppFilterModel::AppFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    sort(0);

    connect(this, &QAbstractItemModel::rowsInserted, this, &AppFilterModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &AppFilterModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &AppFilterModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &AppFilterModel::countChanged);
}

int AppFilterModel::count() const
{
    return rowCount();
}

QString AppFilterModel::filterCategory() const
{
    return m_filterCategory;
}

void AppFilterModel::setFilterCategory(const QString &category)
{
    if (m_filterCategory == category)
        return;
    beginFilterChange();
    m_filterCategory = category;
    endFilterChange();
    emit filterCategoryChanged();
}

QString AppFilterModel::searchText() const
{
    return m_searchText;
}

void AppFilterModel::setSearchText(const QString &text)
{
    if (m_searchText == text)
        return;
    beginFilterChange();
    m_searchText = text;
    endFilterChange();
    emit searchTextChanged();
}

QStringList AppFilterModel::hiddenApps() const
{
    return m_hiddenApps;
}

void AppFilterModel::setHiddenApps(const QStringList &list)
{
    if (m_hiddenApps == list)
        return;
    beginFilterChange();
    m_hiddenApps = list;
    endFilterChange();
    emit hiddenAppsChanged();
}

void AppFilterModel::hideApp(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    if (!idx.isValid())
        return;
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty() && !m_hiddenApps.contains(sid)) {
        beginFilterChange();
        m_hiddenApps.append(sid);
        endFilterChange();
        emit hiddenAppsChanged();
    }
}

void AppFilterModel::unhideApp(const QString &storageId)
{
    if (m_hiddenApps.contains(storageId)) {
        beginFilterChange();
        m_hiddenApps.removeAll(storageId);
        endFilterChange();
        emit hiddenAppsChanged();
    }
}

QStringList AppFilterModel::favoriteApps() const
{
    return m_favoriteApps;
}

void AppFilterModel::setFavoriteApps(const QStringList &list)
{
    if (m_favoriteApps == list)
        return;
    m_favoriteApps = list;
    emit favoriteAppsChanged();
}

bool AppFilterModel::isFavorite(const QString &storageId) const
{
    return m_favoriteApps.contains(storageId);
}

void AppFilterModel::toggleFavorite(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    if (m_favoriteApps.contains(storageId))
        m_favoriteApps.removeAll(storageId);
    else
        m_favoriteApps.append(storageId);
    emit favoriteAppsChanged();
}

QStringList AppFilterModel::recentApps() const
{
    return m_recentApps;
}

void AppFilterModel::setRecentApps(const QStringList &list)
{
    bool changed = (m_recentApps != list);
    m_recentApps = list;
    invalidate();
    if (changed)
        emit recentAppsChanged();
}

int AppFilterModel::maxRecentApps() const
{
    return m_maxRecentApps;
}

void AppFilterModel::setMaxRecentApps(int max)
{
    if (m_maxRecentApps == max)
        return;
    m_maxRecentApps = max;
    emit maxRecentAppsChanged();
}

bool AppFilterModel::isRecent(const QString &storageId) const
{
    return m_recentApps.contains(storageId);
}

QVariantMap AppFilterModel::getByStorageId(const QString &storageId) const
{
    QVariantMap map;
    auto *src = sourceModel();
    if (!src)
        return map;
    for (int i = 0; i < src->rowCount(); ++i) {
        const auto idx = src->index(i, 0);
        if (idx.data(AppModel::StorageIdRole).toString() == storageId) {
            map[QStringLiteral("name")] = idx.data(AppModel::NameRole);
            map[QStringLiteral("iconName")] = idx.data(AppModel::IconRole);
            map[QStringLiteral("desktopFile")] = idx.data(AppModel::DesktopFileRole);
            map[QStringLiteral("storageId")] = idx.data(AppModel::StorageIdRole);
            map[QStringLiteral("genericName")] = idx.data(AppModel::GenericNameRole);
            break;
        }
    }
    return map;
}

bool AppFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const auto idx = sourceModel()->index(sourceRow, 0, sourceParent);

    // Hide hidden apps
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty() && m_hiddenApps.contains(sid))
        return false;

    if (!m_filterCategory.isEmpty()) {
        const auto category = idx.data(AppModel::CategoryRole).toString();
        if (category != m_filterCategory)
            return false;
    }

    if (!m_searchText.isEmpty()) {
        const auto name = idx.data(AppModel::NameRole).toString();
        const auto generic = idx.data(AppModel::GenericNameRole).toString();
        if (!name.contains(m_searchText, Qt::CaseInsensitive)
            && !generic.contains(m_searchText, Qt::CaseInsensitive))
            return false;
    }

    // In "All" view (no category, no search), hide recents from the main grid
    // (they are shown in the header section instead).
    // Skip this when sorting by most-used — all apps stay in the grid.
    if (m_sortMode == Alphabetical
        && m_filterCategory.isEmpty() && m_searchText.isEmpty()
        && !m_recentApps.isEmpty() && m_recentApps.contains(sid))
        return false;

    return true;
}

int AppFilterModel::sortMode() const
{
    return m_sortMode;
}

void AppFilterModel::setSortMode(int mode)
{
    if (m_sortMode == mode)
        return;
    m_sortMode = mode;
    invalidate();
    emit sortModeChanged();
}

QVariantMap AppFilterModel::launchCountsMap() const
{
    QVariantMap map;
    for (auto it = m_launchCounts.cbegin(); it != m_launchCounts.cend(); ++it)
        map.insert(it.key(), it.value());
    return map;
}

void AppFilterModel::setLaunchCountsMap(const QVariantMap &map)
{
    m_launchCounts.clear();
    for (auto it = map.cbegin(); it != map.cend(); ++it)
        m_launchCounts.insert(it.key(), it.value().toInt());
    if (m_sortMode == MostUsed)
        invalidate();
    emit launchCountsChanged();
}

QStringList AppFilterModel::knownApps() const
{
    return m_knownApps;
}

void AppFilterModel::setKnownApps(const QStringList &list)
{
    if (m_knownApps == list)
        return;
    m_knownApps = list;
    emit knownAppsChanged();
}

bool AppFilterModel::isNewApp(const QString &storageId) const
{
    // If knownApps was never set (empty), nothing is "new"
    return !m_knownApps.isEmpty() && !m_knownApps.contains(storageId);
}

void AppFilterModel::markAllKnown()
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    if (!model)
        return;
    QStringList all;
    all.reserve(model->rowCount());
    for (int i = 0; i < model->rowCount(); ++i)
        all.append(model->index(i, 0).data(AppModel::StorageIdRole).toString());
    setKnownApps(all);
}

int AppFilterModel::getLaunchCount(const QString &storageId) const
{
    return m_launchCounts.value(storageId, 0);
}

void AppFilterModel::recordLaunch(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    m_launchCounts[storageId] = m_launchCounts.value(storageId, 0) + 1;
    emit launchCountsChanged();

    // Mark as known when launched
    if (!m_knownApps.contains(storageId)) {
        m_knownApps.append(storageId);
        emit knownAppsChanged();
    }
}

bool AppFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    if (m_sortMode == MostUsed) {
        const auto leftSid = left.data(AppModel::StorageIdRole).toString();
        const auto rightSid = right.data(AppModel::StorageIdRole).toString();
        const int leftCount = m_launchCounts.value(leftSid, 0);
        const int rightCount = m_launchCounts.value(rightSid, 0);
        if (leftCount != rightCount)
            return leftCount > rightCount; // Higher count first
    }
    const auto leftName = left.data(AppModel::NameRole).toString();
    const auto rightName = right.data(AppModel::NameRole).toString();
    return QString::localeAwareCompare(leftName, rightName) < 0;
}

void AppFilterModel::launch(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    const auto sourceIdx = mapToSource(idx);
    auto *model = qobject_cast<AppModel *>(sourceModel());
    if (!model)
        return;

    // Record as recent and track launch count
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty()) {
        m_recentApps.removeAll(sid);
        m_recentApps.prepend(sid);
        while (m_recentApps.size() > m_maxRecentApps)
            m_recentApps.removeLast();
        invalidate();
        emit recentAppsChanged();
        recordLaunch(sid);
    }

    model->launch(sourceIdx.row());
}

void AppFilterModel::launchByStorageId(const QString &storageId)
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    if (!model)
        return;

    // Find the source row for this storageId
    for (int i = 0; i < model->rowCount(); ++i) {
        const auto idx = model->index(i, 0);
        if (idx.data(AppModel::StorageIdRole).toString() == storageId) {
            // Record as recent and track launch count
            m_recentApps.removeAll(storageId);
            m_recentApps.prepend(storageId);
            while (m_recentApps.size() > m_maxRecentApps)
                m_recentApps.removeLast();
            invalidate();
            emit recentAppsChanged();
            recordLaunch(storageId);

            model->launch(i);
            return;
        }
    }
}

QStringList AppFilterModel::categories() const
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    return model ? model->categories() : QStringList();
}

QVariantMap AppFilterModel::get(int proxyRow) const
{
    QVariantMap map;
    const auto idx = index(proxyRow, 0);
    if (!idx.isValid())
        return map;
    const auto roles = roleNames();
    for (auto it = roles.cbegin(); it != roles.cend(); ++it)
        map.insert(QString::fromUtf8(it.value()), idx.data(it.key()));
    return map;
}
