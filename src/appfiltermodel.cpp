/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appfiltermodel.h"

#include "appactionid.h"
#include "appmodel.h"
#include "appresolver.h"
#include "categoryqueries.h"
#include "launchstatestore.h"

#include <KIconLoader>
#include <KSharedConfig>

namespace
{
// completionFor() scans only the top-ranked rows for an inline-completion word,
// so it stays cheap enough to run synchronously on every keystroke (the heavy
// filter pass is what's deferred in QML).
constexpr int kCompletionScanLimit = 25;
}

// --- Constructor ---

AppFilterModel::AppFilterModel(QObject *parent)
    : FilterProxyModel(parent)
    // In memory (no file) until the controller hands over the shared store.
    , m_ownState(std::make_unique<LaunchStateStore>(KSharedConfig::openConfig(QString(), KConfig::SimpleConfig)))
{
    setLaunchState(m_ownState.get());
    setSortCaseSensitivity(Qt::CaseInsensitive);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    sort(0);

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

    // The row index and the row-score cache are rebuilt lazily on first read
    // and dropped whenever the source model changes shape or row data. Hooks
    // attached via sourceModelChanged so we don't need to override
    // setSourceModel (moc generates a duplicate definition for
    // QSortFilterProxyModel overrides that don't carry Q_INVOKABLE).
    connect(this, &QSortFilterProxyModel::sourceModelChanged, this, [this]() {
        m_index.setModel(sourceModel());
        m_ranking.invalidate();
        auto *src = sourceModel();
        if (!src) {
            return;
        }
        // Row-set changes shift source rows + their name/sid/category, so the
        // row-score cache goes with the row index. The dataChanged below is
        // icon-only (AppModel) and touches no RowScore field, so it
        // deliberately leaves the row-score cache alone.
        auto invalidateBoth = [this]() {
            m_index.invalidate();
            m_ranking.invalidate();
        };
        connect(src, &QAbstractItemModel::modelReset, this, invalidateBoth);
        // After a database reload the app set may have shrunk (uninstall); drop any
        // recents whose app is now gone so the recents row doesn't show dead ids.
        connect(src, &QAbstractItemModel::modelReset, this, &AppFilterModel::pruneRecentsToExisting);
        connect(src, &QAbstractItemModel::rowsInserted, this, invalidateBoth);
        connect(src, &QAbstractItemModel::rowsRemoved, this, invalidateBoth);
        // Per-row data updates (e.g. icon refresh) keep the storage id
        // map valid but invalidate the haystacks.
        connect(src, &QAbstractItemModel::dataChanged, this, [this]() {
            m_index.invalidateHaystacks();
        });
    });
}

AppFilterModel::~AppFilterModel() = default;

void AppFilterModel::setLaunchState(LaunchStateStore *state)
{
    if (!state || state == m_state) {
        return;
    }
    if (m_state) {
        disconnect(m_state, nullptr, this, nullptr);
    }
    m_state = state;
    connect(state, &LaunchStateStore::hiddenAppsChanged, this, [this]() {
        refilter();
        Q_EMIT hiddenAppsChanged();
    });
    connect(state, &LaunchStateStore::recentAppsChanged, this, [this]() {
        // Recents leave the All grid (see filterAcceptsRow).
        invalidate();
        Q_EMIT recentAppsChanged();
    });
    connect(state, &LaunchStateStore::launchCountsChanged, this, [this]() {
        m_ranking.invalidate(); // cached launchCount changed
        if (m_sortMode == MostUsed) {
            invalidate();
        }
        Q_EMIT launchCountsChanged();
    });
    m_ranking.invalidate();
    invalidate();
    Q_EMIT hiddenAppsChanged();
    Q_EMIT recentAppsChanged();
    Q_EMIT launchCountsChanged();
}

const LaunchBookkeeping &AppFilterModel::book() const
{
    return m_state->book();
}

void AppFilterModel::pruneRecentsToExisting()
{
    const QStringList current = book().recent();
    QStringList kept;
    kept.reserve(current.size());
    for (const auto &sid : current) {
        if (m_index.contains(sid)) {
            kept.append(sid);
        }
    }
    if (kept.size() != current.size()) {
        // The store persists the shorter list and re-sorts us.
        setRecentApps(kept);
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
    if (m_filterCategory == category) {
        return;
    }
    m_filterCategory = category;
    refilter();
    Q_EMIT filterCategoryChanged();
}

QString AppFilterModel::searchText() const
{
    return m_query.text;
}

void AppFilterModel::applySearchText(const QString &text)
{
    m_query = AppSearch::Query::of(text);
    m_ranking.invalidate(); // cached relevance depends on the query
}

void AppFilterModel::setSearchText(const QString &text)
{
    if (m_query.text == text) {
        return;
    }
    applySearchText(text);
    invalidate(); // Re-run filter + sort for relevance ranking
    Q_EMIT searchTextChanged();
}

void AppFilterModel::setSearchState(const QString &text, const QString &category, bool favoritesOnly)
{
    const bool textChanged = m_query.text != text;
    const bool categoryChanged = m_filterCategory != category;
    const bool favoritesChanged = m_showFavoritesOnly != favoritesOnly;
    if (!textChanged && !categoryChanged && !favoritesChanged) {
        return;
    }
    if (textChanged) {
        applySearchText(text);
    }
    m_filterCategory = category;
    m_showFavoritesOnly = favoritesOnly;
    // One pass: the query and favourites mode affect the sort order (see
    // setShowFavoritesOnly), the category only the filter.
    if (textChanged || favoritesChanged) {
        invalidate();
    } else {
        refilter();
    }
    if (categoryChanged) {
        Q_EMIT filterCategoryChanged();
    }
    if (favoritesChanged) {
        Q_EMIT showFavoritesOnlyChanged();
    }
    if (textChanged) {
        Q_EMIT searchTextChanged();
    }
}

QStringList AppFilterModel::hiddenApps() const
{
    return book().hidden();
}

void AppFilterModel::setHiddenApps(const QStringList &list)
{
    m_state->setHiddenApps(list);
}

void AppFilterModel::hideApp(int proxyIndex)
{
    const auto idx = index(proxyIndex, 0);
    if (idx.isValid()) {
        m_state->hide(idx.data(AppModel::StorageIdRole).toString());
    }
}

void AppFilterModel::hideByStorageId(const QString &storageId)
{
    m_state->hide(storageId);
}

void AppFilterModel::unhideApp(const QString &storageId)
{
    m_state->unhide(storageId);
}

QStringList AppFilterModel::favoriteApps() const
{
    return m_ranking.favorites().list();
}

void AppFilterModel::setFavoriteApps(const QStringList &list)
{
    if (!m_ranking.setFavorites(list)) {
        return;
    }
    // Favourite order drives the favourites-only view, and being a favourite
    // ranks search results.
    if (m_showFavoritesOnly || !m_query.isEmpty()) {
        invalidate();
    }
    Q_EMIT favoriteAppsChanged();
}

bool AppFilterModel::isFavorite(const QString &storageId) const
{
    return m_ranking.favorites().contains(storageId);
}

QStringList AppFilterModel::recentApps() const
{
    return book().recent();
}

void AppFilterModel::setRecentApps(const QStringList &list)
{
    m_state->setRecentApps(list);
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
    return book().isRecent(storageId);
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
    return book().launchCountsMap();
}

void AppFilterModel::setLaunchCountsMap(const QVariantMap &map)
{
    m_state->setLaunchCounts(map);
}

void AppFilterModel::setFrecencyScores(const QHash<QString, int> &scores)
{
    if (m_ranking.setFrecencyScores(scores) && m_ranking.useFrecency() && !m_query.isEmpty()) {
        invalidate();
    }
}

void AppFilterModel::setSearchUsesFrecency(bool enabled)
{
    if (m_ranking.setUseFrecency(enabled) && !m_query.isEmpty()) {
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
    if (!m_query.isEmpty()) {
        refilter();
    }
    Q_EMIT searchShowsHiddenChanged();
}

bool AppFilterModel::isHidden(const QString &storageId) const
{
    return book().isHidden(storageId);
}

void AppFilterModel::setNewApps(const QSet<QString> &newApps)
{
    if (m_newApps == newApps) {
        return;
    }
    m_newApps = newApps;
    Q_EMIT newAppsChanged(); // delegates re-read isNewApp
}

bool AppFilterModel::isNewApp(const QString &storageId) const
{
    // The set is computed by NewAppsTracker (recently installed + unused, the
    // Kickoff model); the filter just exposes membership to the delegates.
    return m_newApps.contains(storageId);
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
    // Use invalidate() instead of refilter() because
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
    // Change-detect so a re-sync on every popup open (ModelConfigSync.sync())
    // doesn't re-emit categoriesChanged() and rebuild the QML category bar when
    // nothing changed (#200).
    auto *src = qobject_cast<AppModel *>(sourceModel());
    if (!src || src->useSystemCategories() == enabled) {
        return;
    }
    src->setUseSystemCategories(enabled);
    Q_EMIT useSystemCategoriesChanged();
    Q_EMIT categoriesChanged();
}

int AppFilterModel::getLaunchCount(const QString &storageId) const
{
    return book().launchCount(storageId);
}

QString AppFilterModel::completionFor(const QString &query) const
{
    return AppSearch::completion(*this, query, kCompletionScanLimit);
}

// --- Default apps (mimeapps.list) ---

QStringList AppFilterModel::defaultApps() const
{
    return m_ranking.defaultApps();
}

void AppFilterModel::setDefaultApps(const QStringList &list)
{
    if (!m_ranking.setDefaultApps(list)) {
        return;
    }
    invalidate(); // search ranking depends on this
    Q_EMIT defaultAppsChanged();
}

void AppFilterModel::setPreferredApps(const QSet<QString> &apps)
{
    if (m_ranking.setPreferredApps(apps)) {
        invalidate(); // search ranking depends on this
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
    if (book().isHidden(sid)) {
        if (m_query.isEmpty() || !m_searchShowsHidden) {
            return false;
        }
    }

    // Favorites-only filter
    if (m_showFavoritesOnly) {
        if (sid.isEmpty() || !m_ranking.favorites().contains(sid)) {
            return false;
        }
    }

    if (!m_filterCategory.isEmpty()) {
        const auto itemCategories = idx.data(AppModel::CategoriesRole).toStringList();
        if (!itemCategories.contains(m_filterCategory)) {
            return false;
        }
    }

    if (!m_query.isEmpty() && !m_query.matches(m_index.haystack(sourceRow))) {
        return false;
    }

    // In "All" view (no category, no search), hide recents from the main grid
    // (they are shown in the header section instead).
    // Skip when: sorting by most-used, showing favorites, or filtering by category/search.
    if (m_sortMode == Alphabetical && !m_showFavoritesOnly && m_filterCategory.isEmpty() && m_query.isEmpty() && book().hasRecent() && book().isRecent(sid)) {
        return false;
    }

    return true;
}

// --- Sorting ---

bool AppFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    return m_ranking.lessThan(left, right, {m_query.text, m_showFavoritesOnly, m_sortFavoritesAlphabetically, m_sortMode}, book());
}

// --- Category queries ---

QStringList AppFilterModel::nonEmptyCategories() const
{
    return CategoryQueries::nonEmptyCategories(sourceModel(), [this](const QString &sid) {
        return book().isHidden(sid);
    });
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
    if (storageId.isEmpty()) {
        return map;
    }

    // Jump-list action favourite (applications:<id>?action=<name>, #64): the
    // action's own name and icon on every Plasma, not only where Kicker's
    // AppEntry understands the url.
    if (AppActionId::hasAction(storageId)) {
        return AppResolver::actionData(storageId);
    }

    auto *src = sourceModel();
    const int row = m_index.rowOf(storageId);
    if (!src || row < 0) {
        return map;
    }
    const auto idx = src->index(row, 0);
    map = CategoryQueries::appDataMap(idx);
    map[QStringLiteral("genericName")] = idx.data(AppModel::GenericNameRole);
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
    // The store re-sorts us through its change signals. The launch also
    // reached KActivities (notifyAccessed); UsedAppsProvider picks it up and
    // clears the new-app badge.
    m_state->recordLaunch(storageId, m_maxRecentApps);
}
