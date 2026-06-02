/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appfiltermodel.h"

#include "pluginhelpers.h"

#include <KIO/ApplicationLauncherJob>
#include <KJob>

#include <cstdlib>
#include <limits>

// Qt 6.13 deprecated invalidateFilter() in favour of begin/endFilterChange().
// Suppress the deprecation warning on older Qt where the replacement doesn't exist.
// APPGRID_INVALIDATE_FILTER  — re-run filter only
// APPGRID_INVALIDATE_ALL     — re-run filter + sort (for search relevance ranking)
#if QT_VERSION >= QT_VERSION_CHECK(6, 13, 0)
#define APPGRID_INVALIDATE_FILTER()                                                                                                                            \
    do {                                                                                                                                                       \
        beginFilterChange();                                                                                                                                   \
        endFilterChange();                                                                                                                                     \
    } while (0)
#define APPGRID_INVALIDATE_ALL() invalidate()
#else
#define APPGRID_INVALIDATE_FILTER()                                                                                                                            \
    _Pragma("GCC diagnostic push") _Pragma("GCC diagnostic ignored \"-Wdeprecated-declarations\"") invalidateFilter();                                         \
    _Pragma("GCC diagnostic pop")
#define APPGRID_INVALIDATE_ALL() invalidate()
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
        Q_EMIT groupedByCategoryChanged();
    };
    connect(this, &AppFilterModel::hiddenAppsChanged, this, markGroupedDirty);
    connect(this, &AppFilterModel::showFavoritesOnlyChanged, this, markGroupedDirty);
    connect(this, &AppFilterModel::filterCategoryChanged, this, markGroupedDirty);
    connect(this, &QAbstractItemModel::modelReset, this, markGroupedDirty);

    // storageId → source-row cache and per-row haystack cache: rebuilt
    // lazily on first read, invalidated together whenever the source
    // model changes shape or row data. Hooks attached via
    // sourceModelChanged so we don't need to override setSourceModel
    // (moc generates a duplicate definition for QSortFilterProxyModel
    // overrides that don't carry Q_INVOKABLE).
    connect(this, &QSortFilterProxyModel::sourceModelChanged, this, [this]() {
        invalidateStorageIdCache();
        invalidateHaystackCache();
        auto *src = sourceModel();
        if (!src)
            return;
        auto invalidateBoth = [this]() {
            invalidateStorageIdCache();
            invalidateHaystackCache();
        };
        connect(src, &QAbstractItemModel::modelReset, this, invalidateBoth);
        connect(src, &QAbstractItemModel::rowsInserted, this, invalidateBoth);
        connect(src, &QAbstractItemModel::rowsRemoved, this, invalidateBoth);
        // Per-row data updates (e.g. icon refresh) keep the storage id
        // map valid but invalidate the haystack for that row.
        connect(src, &QAbstractItemModel::dataChanged, this, &AppFilterModel::invalidateHaystackCache);
    });
}

void AppFilterModel::invalidateHaystackCache()
{
    m_haystackCache.clear();
}

QString AppFilterModel::ensureHaystack(int sourceRow) const
{
    const auto cached = m_haystackCache.constFind(sourceRow);
    if (cached != m_haystackCache.constEnd())
        return *cached;

    auto *src = sourceModel();
    if (!src)
        return {};

    const auto idx = src->index(sourceRow, 0);
    QStringList parts{
        idx.data(AppModel::NameRole).toString(),
        idx.data(AppModel::GenericNameRole).toString(),
        idx.data(AppModel::KeywordsRole).toStringList().join(QLatin1Char('\n')),
        idx.data(AppModel::CategoriesRole).toStringList().join(QLatin1Char('\n')),
        idx.data(AppModel::CommentRole).toString(),
        idx.data(AppModel::InstallSourceRole).toString(),
    };
    const QString hay = parts.join(QLatin1Char('\n')).toCaseFolded();
    m_haystackCache.insert(sourceRow, hay);
    return hay;
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

// --- Search helpers (filter + ranking share these) ---

// Relevance tiers used by searchRelevance() and the promotion guard in
// lessThan(). Lower number = better match. Named so the comparison sites
// don't carry bare integers.
constexpr int kTierNamePrefix = 0; // name starts with query
constexpr int kTierNameWordBoundary = 1; // word-boundary substring in name
constexpr int kTierGeneric = 2; // word-boundary in generic name / Comment fallback
constexpr int kTierKeyword = 3; // keyword or category contains query
constexpr int kTierNameMidword = 4; // mid-word substring fallback
constexpr int kTierNoMatch = 5; // filtered out

// Naive plural strip: "games" → "game". Capped at queries of 4+ chars so
// short tokens like "es"/"is"/"os" don't lose their final letter. Lets a
// plural query reach singular-category rows in both the filter step and
// the tier-3 category check. No real stemmer — that's a wider problem;
// this covers the common English case.
static QString singularize(const QString &query)
{
    if (query.size() < 4 || !query.endsWith(QLatin1Char('s'), Qt::CaseInsensitive))
        return {};
    return query.chopped(1);
}

// True when `needle` appears at a word boundary in `haystack` — i.e. at
// position 0 or just after a non-alphanumeric character. Stops a query
// like "ter" from matching "ghostwriter" / "booster" as a meaningful
// substring; those drop to the mid-word fallback tier instead.
static bool containsAtWordBoundary(const QString &haystack, const QString &needle)
{
    if (needle.isEmpty())
        return false;
    int from = 0;
    while (true) {
        const int idx = haystack.indexOf(needle, from, Qt::CaseInsensitive);
        if (idx < 0)
            return false;
        if (idx == 0 || !haystack.at(idx - 1).isLetterOrNumber())
            return true;
        from = idx + 1;
    }
}

// --- Property accessors ---

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
    m_filterCategory = category;
    APPGRID_INVALIDATE_FILTER();
    Q_EMIT filterCategoryChanged();
}

QString AppFilterModel::searchText() const
{
    return m_searchText;
}

void AppFilterModel::setSearchText(const QString &text)
{
    if (m_searchText == text)
        return;
    m_searchText = text;
    m_searchTextLower = text.toCaseFolded();
    m_searchTextLowerSingular = singularize(m_searchTextLower);
    APPGRID_INVALIDATE_ALL(); // Re-run filter + sort for relevance ranking
    Q_EMIT searchTextChanged();
}

QStringList AppFilterModel::hiddenApps() const
{
    return m_hiddenApps;
}

void AppFilterModel::setHiddenApps(const QStringList &list)
{
    if (m_hiddenApps == list)
        return;
    m_hiddenApps = list;
    rebuildHiddenSet();
    APPGRID_INVALIDATE_FILTER();
    Q_EMIT hiddenAppsChanged();
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
        Q_EMIT hiddenAppsChanged();
    }
}

void AppFilterModel::hideByStorageId(const QString &storageId)
{
    if (storageId.isEmpty() || m_hiddenAppsSet.contains(storageId))
        return;
    m_hiddenApps.append(storageId);
    m_hiddenAppsSet.insert(storageId);
    APPGRID_INVALIDATE_FILTER();
    Q_EMIT hiddenAppsChanged();
}

void AppFilterModel::unhideApp(const QString &storageId)
{
    if (m_hiddenAppsSet.remove(storageId)) {
        m_hiddenApps.removeAll(storageId);
        APPGRID_INVALIDATE_FILTER();
        Q_EMIT hiddenAppsChanged();
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
    rebuildFavoriteSet();
    if (m_showFavoritesOnly)
        invalidate();
    Q_EMIT favoriteAppsChanged();
}

bool AppFilterModel::isFavorite(const QString &storageId) const
{
    return m_favoriteAppsSet.contains(storageId);
}

QStringList AppFilterModel::recentApps() const
{
    return m_recentApps;
}

void AppFilterModel::setRecentApps(const QStringList &list)
{
    if (m_recentApps == list)
        return;
    m_recentApps = list;
    rebuildRecentSet();
    invalidate();
    Q_EMIT recentAppsChanged();
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
    Q_EMIT maxRecentAppsChanged();
}

bool AppFilterModel::isRecent(const QString &storageId) const
{
    return m_recentAppsSet.contains(storageId);
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
    Q_EMIT sortModeChanged();
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
    Q_EMIT launchCountsChanged();
}

void AppFilterModel::setFrecencyScores(const QHash<QString, int> &scores)
{
    if (m_frecencyScores == scores)
        return;
    m_frecencyScores = scores;
    if (m_searchUsesFrecency && !m_searchText.isEmpty())
        invalidate();
}

void AppFilterModel::setSearchUsesFrecency(bool enabled)
{
    if (m_searchUsesFrecency == enabled)
        return;
    m_searchUsesFrecency = enabled;
    if (!m_searchText.isEmpty())
        invalidate();
}

bool AppFilterModel::searchShowsHidden() const
{
    return m_searchShowsHidden;
}

void AppFilterModel::setSearchShowsHidden(bool enabled)
{
    if (m_searchShowsHidden == enabled)
        return;
    m_searchShowsHidden = enabled;
    if (!m_searchText.isEmpty()) {
        APPGRID_INVALIDATE_FILTER();
    }
    Q_EMIT searchShowsHiddenChanged();
}

bool AppFilterModel::isHidden(const QString &storageId) const
{
    return !storageId.isEmpty() && m_hiddenAppsSet.contains(storageId);
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
    rebuildKnownSet();
    Q_EMIT knownAppsChanged();
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

bool AppFilterModel::showFavoritesOnly() const
{
    return m_showFavoritesOnly;
}

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
    Q_EMIT showFavoritesOnlyChanged();
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
        Q_EMIT useSystemCategoriesChanged();
        Q_EMIT categoriesChanged();
    }
}

int AppFilterModel::getLaunchCount(const QString &storageId) const
{
    return m_launchCounts.value(storageId, 0);
}

// --- Default apps (mimeapps.list) ---

QStringList AppFilterModel::defaultApps() const
{
    return m_defaultApps;
}

void AppFilterModel::setDefaultApps(const QStringList &list)
{
    if (m_defaultApps == list)
        return;
    m_defaultApps = list;
    m_defaultAppsSet = QSet<QString>(list.cbegin(), list.cend());
    invalidate(); // search ranking depends on this
    Q_EMIT defaultAppsChanged();
}

void AppFilterModel::reloadDefaultApps()
{
    setDefaultApps(PluginHelpers::loadMimeAppsDefaults());
}

void AppFilterModel::recordLaunch(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    m_launchCounts[storageId] = m_launchCounts.value(storageId, 0) + 1;
    Q_EMIT launchCountsChanged();

    if (!m_knownAppsSet.contains(storageId)) {
        m_knownApps.append(storageId);
        m_knownAppsSet.insert(storageId);
        Q_EMIT knownAppsChanged();
    }
}

// --- Filtering ---

bool AppFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const auto idx = sourceModel()->index(sourceRow, 0, sourceParent);

    // Hide hidden apps — except when the user is actively searching
    // and the searchShowsHidden opt-in has been turned on. Lets a
    // deliberately hidden tool stay findable by name (when the user
    // chooses) without un-hiding it from the grid.
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    if (!sid.isEmpty() && m_hiddenAppsSet.contains(sid)) {
        if (m_searchText.isEmpty() || !m_searchShowsHidden)
            return false;
    }

    // Favorites-only filter
    if (m_showFavoritesOnly) {
        if (sid.isEmpty() || !m_favoriteAppsSet.contains(sid))
            return false;
    }

    if (!m_filterCategory.isEmpty()) {
        const auto itemCategories = idx.data(AppModel::CategoriesRole).toStringList();
        if (!itemCategories.contains(m_filterCategory))
            return false;
    }

    if (!m_searchTextLower.isEmpty()) {
        // Match against the pre-folded "name\ngeneric\nkw…\ncategories\n
        // comment\nsource" haystack so a single case-sensitive contains()
        // replaces multiple case-insensitive ones. Plural queries also try
        // the singular form so "games" still reaches a row whose category
        // is "Game"/"ArcadeGame"/etc.
        const auto &haystack = ensureHaystack(sourceRow);
        if (!haystack.contains(m_searchTextLower) && (m_searchTextLowerSingular.isEmpty() || !haystack.contains(m_searchTextLowerSingular)))
            return false;
    }

    // In "All" view (no category, no search), hide recents from the main grid
    // (they are shown in the header section instead).
    // Skip when: sorting by most-used, showing favorites, or filtering by category/search.
    if (m_sortMode == Alphabetical && !m_showFavoritesOnly && m_filterCategory.isEmpty() && m_searchText.isEmpty() && !m_recentAppsSet.isEmpty()
        && m_recentAppsSet.contains(sid))
        return false;

    return true;
}

// --- Sorting ---

// Search relevance: lower score = better match.
//   0 = name prefix
//   1 = word-boundary substring in name
//   2 = word-boundary substring in generic name
//   3 = keyword contains
//   4 = mid-word substring in name (deep fallback — never out-ranks 0..3)
//   5 = no match
static int searchRelevance(const QModelIndex &idx, const QString &query)
{
    if (query.isEmpty())
        return kTierNoMatch;

    const auto name = idx.data(AppModel::NameRole).toString();
    if (name.startsWith(query, Qt::CaseInsensitive))
        return kTierNamePrefix;
    if (containsAtWordBoundary(name, query))
        return kTierNameWordBoundary;

    const auto generic = idx.data(AppModel::GenericNameRole).toString();
    if (containsAtWordBoundary(generic, query))
        return kTierGeneric;
    // Fallback: many .desktop files omit GenericName entirely (third-party
    // apps especially), leaving Comment as the only descriptive field.
    // Treat it as tier 2 only when GenericName is missing so apps that
    // properly fill both don't get double-counted.
    if (generic.isEmpty()) {
        const auto comment = idx.data(AppModel::CommentRole).toString();
        if (containsAtWordBoundary(comment, query))
            return kTierGeneric;
    }

    const auto keywords = idx.data(AppModel::KeywordsRole).toStringList();
    for (const auto &kw : keywords) {
        if (kw.contains(query, Qt::CaseInsensitive))
            return kTierKeyword;
    }

    // Categories share tier 3: typing "game" or "office" should pull in
    // the matching freedesktop category siblings (Game, ArcadeGame,
    // OfficeApp …). Plural queries also test the singularized form so
    // "games" matches "Game" / "ArcadeGame" — see singularize() above.
    const auto categories = idx.data(AppModel::CategoriesRole).toStringList();
    const QString singularQuery = singularize(query);
    for (const auto &cat : categories) {
        if (cat.contains(query, Qt::CaseInsensitive))
            return kTierKeyword;
        if (!singularQuery.isEmpty() && cat.contains(singularQuery, Qt::CaseInsensitive))
            return kTierKeyword;
    }

    if (name.contains(query, Qt::CaseInsensitive))
        return kTierNameMidword;

    return kTierNoMatch;
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
        // rebuildFavoriteSet(). A sid missing from the map gets the
        // sentinel position so it sorts after every real entry.
        constexpr int kSortToEnd = std::numeric_limits<int>::max();
        return m_favoritePositions.value(leftSid, kSortToEnd) < m_favoritePositions.value(rightSid, kSortToEnd);
    }

    // When searching, rank by match relevance first
    if (!m_searchText.isEmpty()) {
        const int leftRel = searchRelevance(left, m_searchText);
        const int rightRel = searchRelevance(right, m_searchText);

        const auto leftSid = left.data(AppModel::StorageIdRole).toString();
        const auto rightSid = right.data(AppModel::StorageIdRole).toString();
        // Frecency (when opted in via ConfigSearch) substitutes the raw
        // launchCount everywhere the search tiebreak / tier-promotion looks
        // it up — same code paths, time-weighted input.
        const auto &counts = (m_searchUsesFrecency && !m_frecencyScores.isEmpty()) ? m_frecencyScores : m_launchCounts;
        const int leftCount = counts.value(leftSid, 0);
        const int rightCount = counts.value(rightSid, 0);

        if (leftRel != rightRel) {
            // Promotion: a heavily used app may jump up exactly one tier
            // (so a frequent keyword-match outranks a never-launched
            // generic-match). The endpoint tiers are inviolate, never
            // crossed by launch count:
            //   0 — name prefix (must always win)
            //   4 — mid-word substring fallback (must always lose)
            // Promotion endpoints (inviolate, never crossed by counts):
            //   kTierNamePrefix — must always win
            //   kTierNameMidword — must always lose
            const bool endpointInvolved =
                leftRel == kTierNamePrefix || rightRel == kTierNamePrefix || leftRel == kTierNameMidword || rightRel == kTierNameMidword;
            // Also block the generic↔keyword boundary so a heavy *keyword*
            // match can't leap past a generic-name / Comment match.
            // Keywords are a marketing tag bag (Discover lists "games"
            // alongside "snap" and "addons"); generic/Comment text is a
            // semantic signal. The promotions that motivated the rule
            // (name-substring vs generic, keyword vs mid-word) still fire.
            const bool keywordVsGenericBoundary =
                (leftRel == kTierGeneric && rightRel == kTierKeyword) || (leftRel == kTierKeyword && rightRel == kTierGeneric);
            if (!endpointInvolved && !keywordVsGenericBoundary && std::abs(leftRel - rightRel) <= 1 && leftCount != rightCount) {
                return leftCount > rightCount;
            }
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

bool AppFilterModel::sortFavoritesAlphabetically() const
{
    return m_sortFavoritesAlphabetically;
}

void AppFilterModel::setSortFavoritesAlphabetically(bool enabled)
{
    if (m_sortFavoritesAlphabetically == enabled)
        return;
    m_sortFavoritesAlphabetically = enabled;
    if (m_showFavoritesOnly)
        invalidate();
    Q_EMIT sortFavoritesAlphabeticallyChanged();
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
    Q_EMIT recentAppsChanged();
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
