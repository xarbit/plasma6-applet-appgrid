/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appfiltermodel.h"

#include "defaultappsresolver.h"
#include "searchranking.h"

#include <KIconLoader>

#include <cstdlib>
#include <limits>

// Re-run only the filter (not the sort). Qt 6.13 replaced invalidateFilter()
// with begin/endFilterChange(); bridge both without leaking a deprecation
// warning on the older path. Sort-affecting changes call invalidate() directly.
void AppFilterModel::invalidateFilterCompat()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 13, 0)
    beginFilterChange();
    endFilterChange();
#else
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    invalidateFilter();
    QT_WARNING_POP
#endif
}

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

    // Icon refresh on KIconLoader::iconChanged, which fires for both an icon
    // file replaced on disk (#86) and a system icon-theme switch (#103). The app
    // icon names don't change, so QML's Kirigami.Icon won't re-resolve and the
    // visible grid keeps stale pixmaps until delegates recycle on scroll. Bump a
    // generation the delegates watch to force an in-place reload — no full model
    // reset (keeps scroll + selection) and not QIcon::setThemeName, whose global
    // override locked the whole process and blocked later theme switches (#103).
    connect(KIconLoader::global(), &KIconLoader::iconChanged, this, [this]() {
        ++m_iconGeneration;
        Q_EMIT iconGenerationChanged();
    });

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
        invalidateRowScoreCache();
        auto *src = sourceModel();
        if (!src) {
            return;
        }
        // Row-set changes shift source rows + their name/sid/category, so the
        // row-score cache goes with the storage-id / haystack caches. The
        // dataChanged below is icon-only (AppModel) and touches no RowScore
        // field, so it deliberately leaves the row-score cache alone.
        auto invalidateBoth = [this]() {
            invalidateStorageIdCache();
            invalidateHaystackCache();
            invalidateRowScoreCache();
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
    if (cached != m_haystackCache.constEnd()) {
        return *cached;
    }

    auto *src = sourceModel();
    if (!src) {
        return {};
    }

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
    if (!m_storageIdCacheDirty) {
        return;
    }
    m_storageIdToSourceRow.clear();
    auto *src = sourceModel();
    if (src) {
        const int n = src->rowCount();
        m_storageIdToSourceRow.reserve(n);
        for (int i = 0; i < n; ++i) {
            const auto sid = src->index(i, 0).data(AppModel::StorageIdRole).toString();
            if (!sid.isEmpty()) {
                m_storageIdToSourceRow.insert(sid, i);
            }
        }
    }
    m_storageIdCacheDirty = false;
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
    if (m_filterCategory == category) {
        return;
    }
    m_filterCategory = category;
    invalidateFilterCompat();
    Q_EMIT filterCategoryChanged();
}

QString AppFilterModel::searchText() const
{
    return m_searchText;
}

void AppFilterModel::setSearchText(const QString &text)
{
    if (m_searchText == text) {
        return;
    }
    m_searchText = text;
    m_searchTextLower = text.toCaseFolded();
    m_searchTextLowerSingular = SearchRanking::singularize(m_searchTextLower);
    invalidateRowScoreCache(); // cached relevance depends on the query
    invalidate(); // Re-run filter + sort for relevance ranking
    Q_EMIT searchTextChanged();
}

QStringList AppFilterModel::hiddenApps() const
{
    return m_book.hidden();
}

void AppFilterModel::setHiddenApps(const QStringList &list)
{
    if (!m_book.setHidden(list)) {
        return;
    }
    invalidateFilterCompat();
    Q_EMIT hiddenAppsChanged();
}

void AppFilterModel::hideApp(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    if (!idx.isValid()) {
        return;
    }
    if (m_book.hide(idx.data(AppModel::StorageIdRole).toString())) {
        invalidateFilterCompat();
        Q_EMIT hiddenAppsChanged();
    }
}

void AppFilterModel::hideByStorageId(const QString &storageId)
{
    if (m_book.hide(storageId)) {
        invalidateFilterCompat();
        Q_EMIT hiddenAppsChanged();
    }
}

void AppFilterModel::unhideApp(const QString &storageId)
{
    if (m_book.unhide(storageId)) {
        invalidateFilterCompat();
        Q_EMIT hiddenAppsChanged();
    }
}

QStringList AppFilterModel::favoriteApps() const
{
    return m_book.favorites();
}

void AppFilterModel::setFavoriteApps(const QStringList &list)
{
    if (!m_book.setFavorites(list)) {
        return;
    }
    if (m_showFavoritesOnly) {
        invalidate();
    }
    Q_EMIT favoriteAppsChanged();
}

bool AppFilterModel::isFavorite(const QString &storageId) const
{
    return m_book.isFavorite(storageId);
}

QStringList AppFilterModel::recentApps() const
{
    return m_book.recent();
}

void AppFilterModel::setRecentApps(const QStringList &list)
{
    if (!m_book.setRecent(list)) {
        return;
    }
    invalidate();
    Q_EMIT recentAppsChanged();
}

int AppFilterModel::maxRecentApps() const
{
    return m_maxRecentApps;
}

void AppFilterModel::setMaxRecentApps(int max)
{
    if (m_maxRecentApps == max) {
        return;
    }
    m_maxRecentApps = max;
    Q_EMIT maxRecentAppsChanged();
}

bool AppFilterModel::isRecent(const QString &storageId) const
{
    return m_book.isRecent(storageId);
}

int AppFilterModel::sortMode() const
{
    return m_sortMode;
}

void AppFilterModel::setSortMode(int mode)
{
    if (m_sortMode == mode) {
        return;
    }
    m_sortMode = mode;
    invalidate();
    Q_EMIT sortModeChanged();
}

QVariantMap AppFilterModel::launchCountsMap() const
{
    return m_book.launchCountsMap();
}

void AppFilterModel::setLaunchCountsMap(const QVariantMap &map)
{
    if (!m_book.setLaunchCountsFromMap(map)) {
        return; // no change — skip the emit/writeback/re-sort (e.g. re-sync on every open)
    }
    invalidateRowScoreCache(); // cached launchCount changed
    if (m_sortMode == MostUsed) {
        invalidate();
    }
    Q_EMIT launchCountsChanged();
}

void AppFilterModel::setFrecencyScores(const QHash<QString, int> &scores)
{
    if (m_frecencyScores == scores) {
        return;
    }
    m_frecencyScores = scores;
    if (m_searchUsesFrecency && !m_searchText.isEmpty()) {
        invalidate();
    }
}

void AppFilterModel::setSearchUsesFrecency(bool enabled)
{
    if (m_searchUsesFrecency == enabled) {
        return;
    }
    m_searchUsesFrecency = enabled;
    if (!m_searchText.isEmpty()) {
        invalidate();
    }
}

bool AppFilterModel::searchShowsHidden() const
{
    return m_searchShowsHidden;
}

void AppFilterModel::setSearchShowsHidden(bool enabled)
{
    if (m_searchShowsHidden == enabled) {
        return;
    }
    m_searchShowsHidden = enabled;
    if (!m_searchText.isEmpty()) {
        invalidateFilterCompat();
    }
    Q_EMIT searchShowsHiddenChanged();
}

bool AppFilterModel::isHidden(const QString &storageId) const
{
    return m_book.isHidden(storageId);
}

QStringList AppFilterModel::knownApps() const
{
    return m_book.known();
}

void AppFilterModel::setKnownApps(const QStringList &list)
{
    if (!m_book.setKnown(list)) {
        return;
    }
    Q_EMIT knownAppsChanged();
}

bool AppFilterModel::isNewApp(const QString &storageId) const
{
    return m_book.isNew(storageId);
}

void AppFilterModel::markAllKnown()
{
    auto *src = sourceModel();
    if (!src) {
        return;
    }
    QStringList all;
    all.reserve(src->rowCount());
    for (int i = 0; i < src->rowCount(); ++i) {
        all.append(src->index(i, 0).data(AppModel::StorageIdRole).toString());
    }
    setKnownApps(all);
}

bool AppFilterModel::showFavoritesOnly() const
{
    return m_showFavoritesOnly;
}

void AppFilterModel::setShowFavoritesOnly(bool enabled)
{
    if (m_showFavoritesOnly == enabled) {
        return;
    }
    m_showFavoritesOnly = enabled;
    // Use invalidate() instead of invalidateFilterCompat() because
    // toggling favorites mode changes the sort order (lessThan sorts by
    // favorite position when enabled, alphabetical otherwise).
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
    return m_book.launchCount(storageId);
}

QString AppFilterModel::completionFor(const QString &query) const
{
    if (query.isEmpty()) {
        return {};
    }
    const QString folded = query.toCaseFolded();
    const int limit = qMin(rowCount(), 25);

    // Pass 1: an app whose *name* starts with the query — complete the whole
    // name (e.g. "vi" → "Visual Studio Code"), highest-ranked first.
    for (int i = 0; i < limit; ++i) {
        const QString name = index(i, 0).data(AppModel::NameRole).toString();
        if (name.size() > query.size() && name.toCaseFolded().startsWith(folded)) {
            return name;
        }
    }

    // Pass 2: no name prefix-matched — complete to the best matching *word*
    // across name / generic name / keywords, so a fuzzy top hit (a terminal
    // named "Ghostty") still completes "te" → "terminal" from its term.
    for (int i = 0; i < limit; ++i) {
        const auto idx = index(i, 0);
        const QString fields[] = {
            idx.data(AppModel::NameRole).toString(),
            idx.data(AppModel::GenericNameRole).toString(),
        };
        for (const auto &field : fields) {
            const QString word = SearchRanking::completionWord(field, query);
            if (!word.isEmpty()) {
                return word;
            }
        }
        const auto keywords = idx.data(AppModel::KeywordsRole).toStringList();
        for (const auto &keyword : keywords) {
            const QString word = SearchRanking::completionWord(keyword, query);
            if (!word.isEmpty()) {
                return word;
            }
        }
    }
    return {};
}

// --- Default apps (mimeapps.list) ---

QStringList AppFilterModel::defaultApps() const
{
    return m_defaultApps;
}

void AppFilterModel::setDefaultApps(const QStringList &list)
{
    if (m_defaultApps == list) {
        return;
    }
    m_defaultApps = list;
    m_defaultAppsSet = QSet<QString>(list.cbegin(), list.cend());
    invalidateRowScoreCache(); // cached isDefault changed
    invalidate(); // search ranking depends on this
    Q_EMIT defaultAppsChanged();
}

void AppFilterModel::reloadDefaultApps()
{
    // DefaultAppsResolver reads every source (mimeapps, KApplicationTrader,
    // kdeglobals). setDefaultApps already change-detects + re-sorts + notifies
    // for the broad default set; handle the preferred (role-default) set here.
    const auto resolved = DefaultAppsResolver::resolve();
    setDefaultApps(QStringList(resolved.defaults.cbegin(), resolved.defaults.cend()));
    if (resolved.preferred != m_preferredAppsSet) {
        m_preferredAppsSet = resolved.preferred;
        invalidateRowScoreCache(); // cached isPreferred changed
        invalidate();
    }
}

void AppFilterModel::recordLaunch(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    m_book.bumpLaunch(storageId);
    invalidateRowScoreCache(); // cached launchCount changed
    Q_EMIT launchCountsChanged();

    if (m_book.addKnown(storageId)) {
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
    if (m_book.isHidden(sid)) {
        if (m_searchText.isEmpty() || !m_searchShowsHidden) {
            return false;
        }
    }

    // Favorites-only filter
    if (m_showFavoritesOnly) {
        if (sid.isEmpty() || !m_book.isFavorite(sid)) {
            return false;
        }
    }

    if (!m_filterCategory.isEmpty()) {
        const auto itemCategories = idx.data(AppModel::CategoriesRole).toStringList();
        if (!itemCategories.contains(m_filterCategory)) {
            return false;
        }
    }

    if (!m_searchTextLower.isEmpty()) {
        // Match against the pre-folded "name\ngeneric\nkw…\ncategories\n
        // comment\nsource" haystack so a single case-sensitive contains()
        // replaces multiple case-insensitive ones. Plural queries also try
        // the singular form so "games" still reaches a row whose category
        // is "Game"/"ArcadeGame"/etc.
        const auto &haystack = ensureHaystack(sourceRow);
        if (!haystack.contains(m_searchTextLower) && (m_searchTextLowerSingular.isEmpty() || !haystack.contains(m_searchTextLowerSingular))) {
            return false;
        }
    }

    // In "All" view (no category, no search), hide recents from the main grid
    // (they are shown in the header section instead).
    // Skip when: sorting by most-used, showing favorites, or filtering by category/search.
    if (m_sortMode == Alphabetical && !m_showFavoritesOnly && m_filterCategory.isEmpty() && m_searchText.isEmpty() && m_book.hasRecent()
        && m_book.isRecent(sid)) {
        return false;
    }

    return true;
}

// --- Sorting ---

// Reads the app's text roles off @p idx and delegates to the pure
// SearchRanking::relevance(). Lower score = better match.
static int searchRelevance(const QModelIndex &idx, const QString &query)
{
    return SearchRanking::relevance(idx.data(AppModel::NameRole).toString(),
                                    idx.data(AppModel::GenericNameRole).toString(),
                                    idx.data(AppModel::CommentRole).toString(),
                                    idx.data(AppModel::KeywordsRole).toStringList(),
                                    idx.data(AppModel::CategoriesRole).toStringList(),
                                    query);
}

const AppFilterModel::RowScore &AppFilterModel::rowScore(const QModelIndex &sourceIndex) const
{
    // lessThan() is handed *source* indices; key by the source row, which is
    // stable across a re-sort — so sorting alone (the per-keystroke case)
    // never invalidates the cache.
    const int sourceRow = sourceIndex.row();
    const auto cached = m_rowScoreCache.constFind(sourceRow);
    if (cached != m_rowScoreCache.constEnd()) {
        return *cached;
    }

    RowScore s;
    s.sid = sourceIndex.data(AppModel::StorageIdRole).toString();
    s.name = sourceIndex.data(AppModel::NameRole).toString();
    s.category = sourceIndex.data(AppModel::CategoryRole).toString();
    s.launchCount = m_book.launchCount(s.sid);
    s.isDefault = m_defaultAppsSet.contains(s.sid);
    s.isPreferred = m_preferredAppsSet.contains(s.sid);
    // Relevance only matters while searching; skip its role reads + case-folds
    // in the alphabetical / most-used / by-category sort modes.
    if (!m_searchText.isEmpty()) {
        s.relevance = searchRelevance(sourceIndex, m_searchText);
    }
    return *m_rowScoreCache.insert(sourceRow, s);
}

void AppFilterModel::invalidateRowScoreCache()
{
    m_rowScoreCache.clear();
}

bool AppFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    const RowScore &l = rowScore(left);
    const RowScore &r = rowScore(right);

    // In favorites mode, sort by position in favoriteApps list — unless the
    // user opted into alphabetical ordering.
    if (m_showFavoritesOnly) {
        if (m_sortFavoritesAlphabetically) {
            return QString::localeAwareCompare(l.name, r.name) < 0;
        }
        // O(1) position lookup via LaunchBookkeeping. A sid missing from the
        // favorites gets the sentinel position so it sorts after every real
        // entry.
        constexpr int kSortToEnd = std::numeric_limits<int>::max();
        return m_book.favoritePosition(l.sid, kSortToEnd) < m_book.favoritePosition(r.sid, kSortToEnd);
    }

    // When searching, rank by match relevance first
    if (!m_searchText.isEmpty()) {
        const int leftRel = l.relevance;
        const int rightRel = r.relevance;
        // Frecency (when opted in via ConfigSearch) substitutes the raw
        // launchCount everywhere the search tiebreak / tier-promotion looks it
        // up — same paths, time-weighted input. O(1) hash by the cached sid,
        // so it stays live without caching frecency itself.
        const bool useFrecency = m_searchUsesFrecency && !m_frecencyScores.isEmpty();
        const int leftCount = useFrecency ? m_frecencyScores.value(l.sid, 0) : l.launchCount;
        const int rightCount = useFrecency ? m_frecencyScores.value(r.sid, 0) : r.launchCount;

        if (leftRel != rightRel) {
            // Promotion: a heavily used app may jump up exactly one tier (so a
            // frequent keyword-match outranks a never-launched generic-match).
            // Endpoint tiers are inviolate, never crossed by launch count:
            //   TierNamePrefix — must always win
            //   TierNameMidword — must always lose
            const bool endpointInvolved = leftRel == SearchRanking::TierNamePrefix || rightRel == SearchRanking::TierNamePrefix
                || leftRel == SearchRanking::TierNameMidword || rightRel == SearchRanking::TierNameMidword;
            // Also block the generic↔keyword boundary so a heavy *keyword*
            // match can't leap past a generic-name / Comment match. Keywords
            // are a marketing tag bag; generic/Comment text is a semantic
            // signal. The promotions that motivated the rule (name-substring
            // vs generic, keyword vs mid-word) still fire.
            const bool keywordVsGenericBoundary = (leftRel == SearchRanking::TierGeneric && rightRel == SearchRanking::TierKeyword)
                || (leftRel == SearchRanking::TierKeyword && rightRel == SearchRanking::TierGeneric);
            if (!endpointInvolved && !keywordVsGenericBoundary && std::abs(leftRel - rightRel) <= 1 && leftCount != rightCount) {
                return leftCount > rightCount;
            }
            return leftRel < rightRel;
        }

        // Within the same relevance tier, the user's role defaults (default
        // browser / mail / file manager / terminal) outrank everything —
        // including other mime defaults and launch count / frecency.
        if (l.isPreferred != r.isPreferred) {
            return l.isPreferred; // true sorts before false
        }

        // Then any other mime default (e.g. the text editor for text/plain).
        if (l.isDefault != r.isDefault) {
            return l.isDefault;
        }

        if (leftCount != rightCount) {
            return leftCount > rightCount;
        }
    } else if (m_sortMode == MostUsed) {
        if (l.launchCount != r.launchCount) {
            return l.launchCount > r.launchCount;
        }
    } else if (m_sortMode == ByCategory) {
        const int cmp = QString::localeAwareCompare(l.category, r.category);
        if (cmp != 0) {
            return cmp < 0;
        }
    }

    return QString::localeAwareCompare(l.name, r.name) < 0;
}

// --- Category queries ---

QVariantList AppFilterModel::appsByCategory() const
{
    if (!m_groupedByCategoryDirty) {
        return m_groupedByCategoryCache;
    }

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

        for (const auto &cat : cats) {
            catMap[cat].append(app);
        }
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
    if (!src) {
        return {};
    }

    QSet<QString> cats;
    for (int i = 0; i < src->rowCount(); ++i) {
        const auto idx = src->index(i, 0);
        const auto sid = idx.data(AppModel::StorageIdRole).toString();
        if (m_book.isHidden(sid)) {
            continue;
        }
        const auto appCats = idx.data(AppModel::CategoriesRole).toStringList();
        for (const auto &c : appCats) {
            cats.insert(c);
        }
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

QString AppFilterModel::categoryIcon(const QString &category) const
{
    auto *model = qobject_cast<AppModel *>(sourceModel());
    return model ? model->categoryIcon(category) : QString();
}

QVariantMap AppFilterModel::getByStorageId(const QString &storageId) const
{
    QVariantMap map;
    auto *src = sourceModel();
    if (!src || storageId.isEmpty()) {
        return map;
    }
    ensureStorageIdCache();
    const int row = m_storageIdToSourceRow.value(storageId, -1);
    if (row < 0) {
        return map;
    }
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
    if (!idx.isValid()) {
        return map;
    }
    const auto roles = roleNames();
    for (auto it = roles.cbegin(); it != roles.cend(); ++it) {
        map.insert(QString::fromUtf8(it.value()), idx.data(it.key()));
    }
    return map;
}

bool AppFilterModel::sortFavoritesAlphabetically() const
{
    return m_sortFavoritesAlphabetically;
}

void AppFilterModel::setSortFavoritesAlphabetically(bool enabled)
{
    if (m_sortFavoritesAlphabetically == enabled) {
        return;
    }
    m_sortFavoritesAlphabetically = enabled;
    if (m_showFavoritesOnly) {
        invalidate();
    }
    Q_EMIT sortFavoritesAlphabeticallyChanged();
}

// --- Launching ---

void AppFilterModel::recordRecentLaunch(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    m_book.recordRecent(storageId, m_maxRecentApps);
    // Bump the launch count before re-sorting so Most Used reflects this launch
    // on the first click, not the next. recordLaunch clears the row-score cache
    // but does not itself re-sort; the invalidate() below does, now reading the
    // incremented count.
    recordLaunch(storageId);
    invalidate();
    Q_EMIT recentAppsChanged();
}

void AppFilterModel::launch(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    const auto sid = idx.data(AppModel::StorageIdRole).toString();
    // Resolve the source row BEFORE recordRecentLaunch: that call invalidate()s
    // the proxy, freeing the internal mapping `idx` points into — using `idx`
    // (or mapToSource on it) afterwards is a use-after-free. Capture the row
    // now, record the bookkeeping, then launch with the captured row. The
    // bookkeeping runs ahead of the AppModel cast so it stays testable with a
    // non-AppModel stub source (recordRecentLaunch no-ops on an empty sid).
    const int sourceRow = mapToSource(idx).row();
    recordRecentLaunch(sid);

    if (auto *model = qobject_cast<AppModel *>(sourceModel())) {
        model->launch(sourceRow);
    }
}

void AppFilterModel::launchByStorageId(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    ensureStorageIdCache();
    const int row = m_storageIdToSourceRow.value(storageId, -1);
    if (row < 0) {
        return;
    }
    recordRecentLaunch(storageId);
    if (auto *model = qobject_cast<AppModel *>(sourceModel())) {
        model->launch(row);
    }
}
