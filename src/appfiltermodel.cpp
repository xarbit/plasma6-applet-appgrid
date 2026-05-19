/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appfiltermodel.h"

#include <KIO/ApplicationLauncherJob>
#include <KJob>

#include <QFile>
#include <QStandardPaths>
#include <QTextStream>

#include <cstdlib>
#include <limits>

// Qt 6.13 deprecated invalidateFilter() in favour of begin/endFilterChange().
// Suppress the deprecation warning on older Qt where the replacement doesn't exist.
// APPGRID_INVALIDATE_FILTER  — re-run filter only
// APPGRID_INVALIDATE_ALL     — re-run filter + sort (for search relevance ranking)
#if QT_VERSION >= QT_VERSION_CHECK(6, 13, 0)
#define APPGRID_INVALIDATE_FILTER() do { beginFilterChange(); endFilterChange(); } while (0)
#define APPGRID_INVALIDATE_ALL()    invalidate()
#else
#define APPGRID_INVALIDATE_FILTER() \
    _Pragma("GCC diagnostic push") \
    _Pragma("GCC diagnostic ignored \"-Wdeprecated-declarations\"") \
    invalidateFilter(); \
    _Pragma("GCC diagnostic pop")
#define APPGRID_INVALIDATE_ALL()    invalidate()
#endif

// --- Constructor ---

AppFilterModel::AppFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    sort(0);

    reloadDefaultApps();

    // countChanged: modelReset covers invalidate() / setSourceModel; the row
    // signals cover incremental row insertion/removal. Earlier code also
    // connected layoutChanged, which fired alongside modelReset for sort
    // changes and double-emitted countChanged on every filter refresh.
    connect(this, &QAbstractItemModel::rowsInserted, this, &AppFilterModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &AppFilterModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &AppFilterModel::countChanged);

    // groupedByCategory depends on visible rows — re-emit when filter state
    // changes. The lambda marks the cache dirty before the signal travels
    // to QML so the next groupedByCategory read recomputes.
    auto markGroupedDirty = [this]() {
        m_groupedByCategoryDirty = true;
        emit groupedByCategoryChanged();
    };
    connect(this, &AppFilterModel::hiddenAppsChanged, this, markGroupedDirty);
    connect(this, &AppFilterModel::showFavoritesOnlyChanged, this, markGroupedDirty);
    connect(this, &AppFilterModel::filterCategoryChanged, this, markGroupedDirty);
    connect(this, &QAbstractItemModel::modelReset, this, markGroupedDirty);

    // storageId → source-row cache: rebuilt lazily on first read,
    // invalidated whenever the source model changes shape. Hooks attached
    // via sourceModelChanged so we don't need to override setSourceModel
    // (moc generates a duplicate definition for QSortFilterProxyModel
    // overrides that don't carry Q_INVOKABLE).
    connect(this, &QSortFilterProxyModel::sourceModelChanged, this, [this]() {
        invalidateStorageIdCache();
        auto *src = sourceModel();
        if (!src)
            return;
        connect(src, &QAbstractItemModel::modelReset, this,
                &AppFilterModel::invalidateStorageIdCache);
        connect(src, &QAbstractItemModel::rowsInserted, this,
                &AppFilterModel::invalidateStorageIdCache);
        connect(src, &QAbstractItemModel::rowsRemoved, this,
                &AppFilterModel::invalidateStorageIdCache);
    });
}

void AppFilterModel::invalidateStorageIdCache()
{
    m_storageIdToSourceRow.clear();
    m_storageIdCacheDirty = true;
}

void AppFilterModel::ensureStorageIdCache() const
{
    if (!m_storageIdCacheDirty)
        return;
    m_storageIdToSourceRow.clear();
    auto *src = sourceModel();
    if (src) {
        const int n = src->rowCount();
        m_storageIdToSourceRow.reserve(n);
        for (int i = 0; i < n; ++i) {
            const auto sid = src->index(i, 0).data(AppModel::StorageIdRole).toString();
            if (!sid.isEmpty())
                m_storageIdToSourceRow.insert(sid, i);
        }
    }
    m_storageIdCacheDirty = false;
}

void AppFilterModel::rebuildHiddenSet()
{
    m_hiddenAppsSet = QSet<QString>(m_hiddenApps.cbegin(), m_hiddenApps.cend());
}

void AppFilterModel::rebuildFavoriteSet()
{
    m_favoriteAppsSet = QSet<QString>(m_favoriteApps.cbegin(), m_favoriteApps.cend());
    m_favoritePositions.clear();
    m_favoritePositions.reserve(m_favoriteApps.size());
    for (int i = 0; i < m_favoriteApps.size(); ++i)
        m_favoritePositions.insert(m_favoriteApps.at(i), i);
}

void AppFilterModel::rebuildRecentSet()
{
    m_recentAppsSet = QSet<QString>(m_recentApps.cbegin(), m_recentApps.cend());
}

void AppFilterModel::rebuildKnownSet()
{
    m_knownAppsSet = QSet<QString>(m_knownApps.cbegin(), m_knownApps.cend());
}

// --- Property accessors ---

int AppFilterModel::count() const { return rowCount(); }

QString AppFilterModel::filterCategory() const { return m_filterCategory; }

void AppFilterModel::setFilterCategory(const QString &category)
{
    if (m_filterCategory == category)
        return;
    m_filterCategory = category;
    APPGRID_INVALIDATE_FILTER();
    emit filterCategoryChanged();
}

QString AppFilterModel::searchText() const { return m_searchText; }

void AppFilterModel::setSearchText(const QString &text)
{
    if (m_searchText == text)
        return;
    m_searchText = text;
    APPGRID_INVALIDATE_ALL(); // Re-run filter + sort for relevance ranking
    emit searchTextChanged();
}

QStringList AppFilterModel::hiddenApps() const { return m_hiddenApps; }

void AppFilterModel::setHiddenApps(const QStringList &list)
{
    if (m_hiddenApps == list)
        return;
    m_hiddenApps = list;
    rebuildHiddenSet();
    APPGRID_INVALIDATE_FILTER();
    emit hiddenAppsChanged();
}

void AppFilterModel::hideApp(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    if (!idx.isValid())
        return;
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty() && !m_hiddenAppsSet.contains(sid)) {
        m_hiddenApps.append(sid);
        m_hiddenAppsSet.insert(sid);
        APPGRID_INVALIDATE_FILTER();
        emit hiddenAppsChanged();
    }
}

void AppFilterModel::hideByStorageId(const QString &storageId)
{
    if (storageId.isEmpty() || m_hiddenAppsSet.contains(storageId))
        return;
    m_hiddenApps.append(storageId);
    m_hiddenAppsSet.insert(storageId);
    APPGRID_INVALIDATE_FILTER();
    emit hiddenAppsChanged();
}

void AppFilterModel::unhideApp(const QString &storageId)
{
    if (m_hiddenAppsSet.remove(storageId)) {
        m_hiddenApps.removeAll(storageId);
        APPGRID_INVALIDATE_FILTER();
        emit hiddenAppsChanged();
    }
}

QStringList AppFilterModel::favoriteApps() const { return m_favoriteApps; }

void AppFilterModel::setFavoriteApps(const QStringList &list)
{
    if (m_favoriteApps == list)
        return;
    m_favoriteApps = list;
    rebuildFavoriteSet();
    if (m_showFavoritesOnly)
        invalidate();
    emit favoriteAppsChanged();
}

bool AppFilterModel::isFavorite(const QString &storageId) const
{
    return m_favoriteAppsSet.contains(storageId);
}

QStringList AppFilterModel::recentApps() const { return m_recentApps; }

void AppFilterModel::setRecentApps(const QStringList &list)
{
    bool changed = (m_recentApps != list);
    m_recentApps = list;
    rebuildRecentSet();
    invalidate();
    if (changed)
        emit recentAppsChanged();
}

int AppFilterModel::maxRecentApps() const { return m_maxRecentApps; }

void AppFilterModel::setMaxRecentApps(int max)
{
    if (m_maxRecentApps == max)
        return;
    m_maxRecentApps = max;
    emit maxRecentAppsChanged();
}

bool AppFilterModel::isRecent(const QString &storageId) const
{
    return m_recentAppsSet.contains(storageId);
}

int AppFilterModel::sortMode() const { return m_sortMode; }

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

QStringList AppFilterModel::knownApps() const { return m_knownApps; }

void AppFilterModel::setKnownApps(const QStringList &list)
{
    if (m_knownApps == list)
        return;
    m_knownApps = list;
    rebuildKnownSet();
    emit knownAppsChanged();
}

bool AppFilterModel::isNewApp(const QString &storageId) const
{
    return !m_knownAppsSet.isEmpty() && !m_knownAppsSet.contains(storageId);
}

void AppFilterModel::markAllKnown()
{
    auto *src = sourceModel();
    if (!src)
        return;
    QStringList all;
    all.reserve(src->rowCount());
    for (int i = 0; i < src->rowCount(); ++i)
        all.append(src->index(i, 0).data(AppModel::StorageIdRole).toString());
    setKnownApps(all);
}

bool AppFilterModel::showFavoritesOnly() const { return m_showFavoritesOnly; }

void AppFilterModel::setShowFavoritesOnly(bool enabled)
{
    if (m_showFavoritesOnly == enabled)
        return;
    m_showFavoritesOnly = enabled;
    // Use invalidate() instead of APPGRID_INVALIDATE_FILTER() because
    // toggling favorites mode changes the sort order (lessThan sorts by
    // m_favoriteApps position when enabled, alphabetical otherwise).
    // A filter-only refresh would keep the previous sort, causing
    // scrambled icon order on first open after login (#70).
    invalidate();
    emit showFavoritesOnlyChanged();
}

bool AppFilterModel::useSystemCategories() const
{
    auto *src = qobject_cast<AppModel *>(sourceModel());
    return src ? src->useSystemCategories() : false;
}

void AppFilterModel::setUseSystemCategories(bool enabled)
{
    auto *src = qobject_cast<AppModel *>(sourceModel());
    if (src) {
        src->setUseSystemCategories(enabled);
        emit useSystemCategoriesChanged();
        emit categoriesChanged();
    }
}

int AppFilterModel::getLaunchCount(const QString &storageId) const
{
    return m_launchCounts.value(storageId, 0);
}

// --- Default apps (mimeapps.list) ---

QStringList AppFilterModel::defaultApps() const { return m_defaultApps; }

void AppFilterModel::setDefaultApps(const QStringList &list)
{
    if (m_defaultApps == list)
        return;
    m_defaultApps = list;
    m_defaultAppsSet = QSet<QString>(list.cbegin(), list.cend());
    invalidate(); // search ranking depends on this
    emit defaultAppsChanged();
}

QStringList AppFilterModel::parseMimeAppsDefaults(const QString &filePath)
{
    QSet<QString> result;
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};

    QTextStream in(&f);
    bool inDefaults = false;
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.startsWith(QLatin1Char('['))) {
            inDefaults = (line == QLatin1String("[Default Applications]"));
            continue;
        }
        if (!inDefaults || line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq < 0)
            continue;
        // value may contain multiple .desktop entries separated by ';'
        const auto values = line.mid(eq + 1).split(QLatin1Char(';'), Qt::SkipEmptyParts);
        for (const auto &v : values) {
            const QString trimmed = v.trimmed();
            if (!trimmed.isEmpty())
                result.insert(trimmed);
        }
    }
    return QStringList(result.cbegin(), result.cend());
}

void AppFilterModel::reloadDefaultApps()
{
    QSet<QString> all;
    const QStringList paths = {
        QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/mimeapps.list"),
        QStringLiteral("/usr/share/applications/mimeapps.list"),
    };
    for (const auto &path : paths) {
        const auto ids = parseMimeAppsDefaults(path);
        for (const auto &id : ids)
            all.insert(id);
    }
    setDefaultApps(QStringList(all.cbegin(), all.cend()));
}

void AppFilterModel::recordLaunch(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    m_launchCounts[storageId] = m_launchCounts.value(storageId, 0) + 1;
    emit launchCountsChanged();

    if (!m_knownAppsSet.contains(storageId)) {
        m_knownApps.append(storageId);
        m_knownAppsSet.insert(storageId);
        emit knownAppsChanged();
    }
}

// --- Filtering ---

bool AppFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const auto idx = sourceModel()->index(sourceRow, 0, sourceParent);

    // Hide hidden apps
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty() && m_hiddenAppsSet.contains(sid))
        return false;

    // Favorites-only filter
    if (m_showFavoritesOnly) {
        if (sid.isEmpty() || !m_favoriteAppsSet.contains(sid))
            return false;
    }

    if (!m_filterCategory.isEmpty()) {
        const auto categories = idx.data(AppModel::CategoriesRole).toStringList();
        if (!categories.contains(m_filterCategory))
            return false;
    }

    if (!m_searchText.isEmpty()) {
        const auto name = idx.data(AppModel::NameRole).toString();
        const auto generic = idx.data(AppModel::GenericNameRole).toString();
        bool matched = name.contains(m_searchText, Qt::CaseInsensitive)
                    || generic.contains(m_searchText, Qt::CaseInsensitive);

        // Check desktop file keywords (e.g. "browser" finds Firefox)
        if (!matched) {
            const auto keywords = idx.data(AppModel::KeywordsRole).toStringList();
            for (const auto &kw : keywords) {
                if (kw.contains(m_searchText, Qt::CaseInsensitive)) {
                    matched = true;
                    break;
                }
            }
        }

        // Check install source (e.g. "flatpak" finds all Flatpak apps)
        if (!matched) {
            const auto source = idx.data(AppModel::InstallSourceRole).toString();
            if (source.contains(m_searchText, Qt::CaseInsensitive))
                matched = true;
        }

        if (!matched)
            return false;
    }

    // In "All" view (no category, no search), hide recents from the main grid
    // (they are shown in the header section instead).
    // Skip when: sorting by most-used, showing favorites, or filtering by category/search.
    if (m_sortMode == Alphabetical && !m_showFavoritesOnly
        && m_filterCategory.isEmpty() && m_searchText.isEmpty()
        && !m_recentAppsSet.isEmpty() && m_recentAppsSet.contains(sid))
        return false;

    return true;
}

// --- Sorting ---

// Search relevance: lower score = better match.
// 0 = name prefix, 1 = name substring, 2 = generic name, 3 = keyword, 4 = no match.
static int searchRelevance(const QModelIndex &idx, const QString &query)
{
    if (query.isEmpty())
        return 4;

    const auto name = idx.data(AppModel::NameRole).toString();
    if (name.startsWith(query, Qt::CaseInsensitive))
        return 0;
    if (name.contains(query, Qt::CaseInsensitive))
        return 1;

    const auto generic = idx.data(AppModel::GenericNameRole).toString();
    if (generic.contains(query, Qt::CaseInsensitive))
        return 2;

    const auto keywords = idx.data(AppModel::KeywordsRole).toStringList();
    for (const auto &kw : keywords) {
        if (kw.contains(query, Qt::CaseInsensitive))
            return 3;
    }

    return 4;
}

bool AppFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    // In favorites mode, sort by position in favoriteApps list — unless the
    // user opted into alphabetical ordering.
    if (m_showFavoritesOnly) {
        if (m_sortFavoritesAlphabetically) {
            const auto leftName = left.data(AppModel::NameRole).toString();
            const auto rightName = right.data(AppModel::NameRole).toString();
            return QString::localeAwareCompare(leftName, rightName) < 0;
        }
        const auto leftSid = left.data(AppModel::StorageIdRole).toString();
        const auto rightSid = right.data(AppModel::StorageIdRole).toString();
        // O(1) position lookup; m_favoritePositions kept in sync by
        // rebuildFavoriteSet(). Missing sid → sort to end via INT_MAX.
        return m_favoritePositions.value(leftSid, std::numeric_limits<int>::max())
             < m_favoritePositions.value(rightSid, std::numeric_limits<int>::max());
    }

    // When searching, rank by match relevance first
    if (!m_searchText.isEmpty()) {
        const int leftRel = searchRelevance(left, m_searchText);
        const int rightRel = searchRelevance(right, m_searchText);

        const auto leftSid = left.data(AppModel::StorageIdRole).toString();
        const auto rightSid = right.data(AppModel::StorageIdRole).toString();
        const int leftCount = m_launchCounts.value(leftSid, 0);
        const int rightCount = m_launchCounts.value(rightSid, 0);

        if (leftRel != rightRel) {
            // Most-used apps can jump up exactly one relevance tier:
            // e.g. a heavily used keyword-match beats a never-launched
            // generic-match, but a strong prefix-match always wins over a
            // distant keyword-match.
            if (std::abs(leftRel - rightRel) <= 1 && leftCount != rightCount)
                return leftCount > rightCount;
            return leftRel < rightRel;
        }

        // Within the same relevance tier, prefer apps that are the user's
        // mime defaults (e.g. default browser ranks above other browsers)
        const bool leftIsDefault = m_defaultAppsSet.contains(leftSid);
        const bool rightIsDefault = m_defaultAppsSet.contains(rightSid);
        if (leftIsDefault != rightIsDefault)
            return leftIsDefault; // true sorts before false

        if (leftCount != rightCount)
            return leftCount > rightCount;
    } else if (m_sortMode == MostUsed) {
        const auto leftSid = left.data(AppModel::StorageIdRole).toString();
        const auto rightSid = right.data(AppModel::StorageIdRole).toString();
        const int leftCount = m_launchCounts.value(leftSid, 0);
        const int rightCount = m_launchCounts.value(rightSid, 0);
        if (leftCount != rightCount)
            return leftCount > rightCount;
    } else if (m_sortMode == ByCategory) {
        const auto leftCat = left.data(AppModel::CategoryRole).toString();
        const auto rightCat = right.data(AppModel::CategoryRole).toString();
        int cmp = QString::localeAwareCompare(leftCat, rightCat);
        if (cmp != 0)
            return cmp < 0;
    }

    const auto leftName = left.data(AppModel::NameRole).toString();
    const auto rightName = right.data(AppModel::NameRole).toString();
    return QString::localeAwareCompare(leftName, rightName) < 0;
}

// --- Category queries ---

QVariantList AppFilterModel::appsByCategory() const
{
    if (!m_groupedByCategoryDirty)
        return m_groupedByCategoryCache;

    QMap<QString, QVariantList> catMap;
    for (int i = 0; i < rowCount(); ++i) {
        const auto idx = index(i, 0);
        const auto cats = idx.data(AppModel::CategoriesRole).toStringList();

        QVariantMap app;
        app[QStringLiteral("name")] = idx.data(AppModel::NameRole);
        app[QStringLiteral("iconName")] = idx.data(AppModel::IconRole);
        app[QStringLiteral("storageId")] = idx.data(AppModel::StorageIdRole);
        app[QStringLiteral("desktopFile")] = idx.data(AppModel::DesktopFileRole);
        app[QStringLiteral("comment")] = idx.data(AppModel::CommentRole);
        app[QStringLiteral("installSource")] = idx.data(AppModel::InstallSourceRole);
        app[QStringLiteral("proxyIndex")] = i;

        for (const auto &cat : cats)
            catMap[cat].append(app);
    }

    QVariantList result;
    for (auto it = catMap.constBegin(); it != catMap.constEnd(); ++it) {
        QVariantMap section;
        section[QStringLiteral("category")] = it.key();
        section[QStringLiteral("apps")] = it.value();
        result.append(section);
    }
    m_groupedByCategoryCache = result;
    m_groupedByCategoryDirty = false;
    return m_groupedByCategoryCache;
}

QStringList AppFilterModel::nonEmptyCategories() const
{
    auto *src = sourceModel();
    if (!src)
        return {};

    QSet<QString> cats;
    for (int i = 0; i < src->rowCount(); ++i) {
        const auto idx = src->index(i, 0);
        const auto sid = idx.data(AppModel::StorageIdRole).toString();
        if (!sid.isEmpty() && m_hiddenAppsSet.contains(sid))
            continue;
        const auto appCats = idx.data(AppModel::CategoriesRole).toStringList();
        for (const auto &c : appCats)
            cats.insert(c);
    }
    return cats.values();
}

QStringList AppFilterModel::categories() const
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    return model ? model->categories() : QStringList();
}

QString AppFilterModel::categoryMenuPath(const QString &category) const
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    return model ? model->categoryMenuPath(category) : QString();
}

QVariantMap AppFilterModel::getByStorageId(const QString &storageId) const
{
    QVariantMap map;
    auto *src = sourceModel();
    if (!src || storageId.isEmpty())
        return map;
    ensureStorageIdCache();
    const int row = m_storageIdToSourceRow.value(storageId, -1);
    if (row < 0)
        return map;
    const auto idx = src->index(row, 0);
    map[QStringLiteral("name")] = idx.data(AppModel::NameRole);
    map[QStringLiteral("iconName")] = idx.data(AppModel::IconRole);
    map[QStringLiteral("desktopFile")] = idx.data(AppModel::DesktopFileRole);
    map[QStringLiteral("storageId")] = idx.data(AppModel::StorageIdRole);
    map[QStringLiteral("genericName")] = idx.data(AppModel::GenericNameRole);
    map[QStringLiteral("comment")] = idx.data(AppModel::CommentRole);
    map[QStringLiteral("installSource")] = idx.data(AppModel::InstallSourceRole);
    return map;
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

bool AppFilterModel::sortFavoritesAlphabetically() const { return m_sortFavoritesAlphabetically; }

void AppFilterModel::setSortFavoritesAlphabetically(bool enabled)
{
    if (m_sortFavoritesAlphabetically == enabled)
        return;
    m_sortFavoritesAlphabetically = enabled;
    if (m_showFavoritesOnly)
        invalidate();
    emit sortFavoritesAlphabeticallyChanged();
}

// --- Launching ---

void AppFilterModel::recordRecentLaunch(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    m_recentApps.removeAll(storageId);
    m_recentApps.prepend(storageId);
    while (m_recentApps.size() > m_maxRecentApps) {
        m_recentApps.removeLast();
    }
    rebuildRecentSet();
    invalidate();
    emit recentAppsChanged();
    recordLaunch(storageId);
}

void AppFilterModel::launch(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    const auto sourceIdx = mapToSource(idx);
    auto *model = qobject_cast<AppModel *>(sourceModel());
    if (!model)
        return;

    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    recordRecentLaunch(sid);

    model->launch(sourceIdx.row());
}

void AppFilterModel::launchByStorageId(const QString &storageId)
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    if (!model || storageId.isEmpty())
        return;
    ensureStorageIdCache();
    const int row = m_storageIdToSourceRow.value(storageId, -1);
    if (row < 0)
        return;
    recordRecentLaunch(storageId);
    model->launch(row);
}
