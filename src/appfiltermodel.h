/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QSet>
#include <QSortFilterProxyModel>
#include <QStringList>
#include <QVariantMap>

#include "appmodel.h"
#include "launchbookkeeping.h"
#include "searchranking.h"

/**
 * @brief Proxy model adding search, category filtering, and app hiding.
 *
 * Wraps AppModel and provides QML-bindable properties for live filtering.
 * Also exposes convenience methods to launch apps, hide/unhide by storageId,
 * and retrieve row data as a QVariantMap.
 */
class AppFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString filterCategory READ filterCategory WRITE setFilterCategory NOTIFY filterCategoryChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QStringList hiddenApps READ hiddenApps WRITE setHiddenApps NOTIFY hiddenAppsChanged)
    Q_PROPERTY(QStringList favoriteApps READ favoriteApps WRITE setFavoriteApps NOTIFY favoriteAppsChanged)
    Q_PROPERTY(QStringList recentApps READ recentApps WRITE setRecentApps NOTIFY recentAppsChanged)
    Q_PROPERTY(int maxRecentApps READ maxRecentApps WRITE setMaxRecentApps NOTIFY maxRecentAppsChanged)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    Q_PROPERTY(QVariantMap launchCounts READ launchCountsMap WRITE setLaunchCountsMap NOTIFY launchCountsChanged)
    Q_PROPERTY(QStringList knownApps READ knownApps WRITE setKnownApps NOTIFY knownAppsChanged)
    Q_PROPERTY(bool showFavoritesOnly READ showFavoritesOnly WRITE setShowFavoritesOnly NOTIFY showFavoritesOnlyChanged)
    Q_PROPERTY(bool sortFavoritesAlphabetically READ sortFavoritesAlphabetically WRITE setSortFavoritesAlphabetically NOTIFY sortFavoritesAlphabeticallyChanged)
    Q_PROPERTY(bool useSystemCategories READ useSystemCategories WRITE setUseSystemCategories NOTIFY useSystemCategoriesChanged)
    Q_PROPERTY(QVariantList groupedByCategory READ appsByCategory NOTIFY groupedByCategoryChanged)
    Q_PROPERTY(QStringList defaultApps READ defaultApps WRITE setDefaultApps NOTIFY defaultAppsChanged)
    // Opt-in: surface hidden apps in search results so a deliberately
    // hidden tool can still be found by name. Default false — hidden
    // means hidden, including from search; on → search bypasses the
    // hidden-set so a typed name still finds the app without un-hiding
    // it from the grid.
    Q_PROPERTY(bool searchShowsHidden READ searchShowsHidden WRITE setSearchShowsHidden NOTIFY searchShowsHiddenChanged)
    // Bumped on a system icon-theme change so QML icons can force a reload
    // (a same-named icon won't re-resolve on its own).
    Q_PROPERTY(int iconGeneration READ iconGeneration NOTIFY iconGenerationChanged)

public:
    /** Sort modes for the grid view. */
    enum SortMode {
        Alphabetical = 0,
        MostUsed = 1,
        ByCategory = 2,
    };
    Q_ENUM(SortMode)

    explicit AppFilterModel(QObject *parent = nullptr);

    [[nodiscard]] QString filterCategory() const;
    void setFilterCategory(const QString &category);

    [[nodiscard]] QString searchText() const;
    void setSearchText(const QString &text);

    [[nodiscard]] int count() const;
    [[nodiscard]] int iconGeneration() const
    {
        return m_iconGeneration;
    }

    [[nodiscard]] QStringList hiddenApps() const;
    void setHiddenApps(const QStringList &list);

    [[nodiscard]] QStringList favoriteApps() const;
    void setFavoriteApps(const QStringList &list);

    [[nodiscard]] QStringList recentApps() const;
    void setRecentApps(const QStringList &list);

    [[nodiscard]] int maxRecentApps() const;
    void setMaxRecentApps(int max);

    [[nodiscard]] int sortMode() const;
    void setSortMode(int mode);

    [[nodiscard]] QVariantMap launchCountsMap() const;
    void setLaunchCountsMap(const QVariantMap &map);

    [[nodiscard]] QStringList knownApps() const;
    void setKnownApps(const QStringList &list);

    [[nodiscard]] bool showFavoritesOnly() const;
    void setShowFavoritesOnly(bool enabled);

    [[nodiscard]] bool useSystemCategories() const;
    void setUseSystemCategories(bool enabled);

    Q_INVOKABLE void launch(int proxyIndex);
    Q_INVOKABLE void launchByStorageId(const QString &storageId);
    // Bookkeeping side of launch: prepend to recents (capped), bump
    // launch count, add to known. Public so tests can exercise it
    // without triggering KIO::ApplicationLauncherJob.
    Q_INVOKABLE void recordRecentLaunch(const QString &storageId);

    [[nodiscard]] QStringList defaultApps() const;
    void setDefaultApps(const QStringList &list);
    // Load defaults from system + user mimeapps.list and update m_defaultApps.
    Q_INVOKABLE void reloadDefaultApps();

    // Opt-in: substitute KActivities frecency scores for the raw launchCount
    // tiebreak inside search ranking. Off by default; the grid sort is never
    // touched by this regardless of state (see #95 close-out + ConfigSearch).
    void setFrecencyScores(const QHash<QString, int> &scores);
    void setSearchUsesFrecency(bool enabled);

    [[nodiscard]] bool searchShowsHidden() const;
    void setSearchShowsHidden(bool enabled);

    // Cheap membership test for the hidden set — used by RunnerFilterModel
    // so it can apply the same searchShowsHidden gate to KRunner rows,
    // and by QML's context menu to toggle the Hide / Unhide label.
    [[nodiscard]] Q_INVOKABLE bool isHidden(const QString &storageId) const;

    [[nodiscard]] Q_INVOKABLE QStringList categories() const;
    [[nodiscard]] Q_INVOKABLE QString categoryMenuPath(const QString &category) const;
    [[nodiscard]] Q_INVOKABLE QString categoryIcon(const QString &category) const;
    [[nodiscard]] Q_INVOKABLE QVariantMap get(int proxyRow) const;
    Q_INVOKABLE void hideApp(int proxyIndex);
    // Hide by storageId — needed for bulk hide where the proxy index of
    // earlier sids in the batch would shift as each hide invalidates the
    // filter. Idempotent: re-hiding an already-hidden sid is a no-op.
    Q_INVOKABLE void hideByStorageId(const QString &storageId);
    Q_INVOKABLE void unhideApp(const QString &storageId);
    [[nodiscard]] Q_INVOKABLE bool isFavorite(const QString &storageId) const;
    [[nodiscard]] Q_INVOKABLE bool isRecent(const QString &storageId) const;

    [[nodiscard]] bool sortFavoritesAlphabetically() const;
    void setSortFavoritesAlphabetically(bool enabled);
    [[nodiscard]] Q_INVOKABLE QVariantMap getByStorageId(const QString &storageId) const;
    [[nodiscard]] Q_INVOKABLE bool isNewApp(const QString &storageId) const;
    [[nodiscard]] Q_INVOKABLE QVariantList appsByCategory() const;
    [[nodiscard]] Q_INVOKABLE QStringList nonEmptyCategories() const;
    Q_INVOKABLE void markAllKnown();
    [[nodiscard]] Q_INVOKABLE int getLaunchCount(const QString &storageId) const;

    // Inline-completion word for the search field: scans the ranked, filtered
    // rows for the best word (name → generic name → keyword) that starts with
    // @p query, so typing completes to a matching term even when the top
    // result's name itself doesn't start with the input. Empty if none.
    [[nodiscard]] Q_INVOKABLE QString completionFor(const QString &query) const;

Q_SIGNALS:
    void iconGenerationChanged();
    void defaultAppsChanged();
    void filterCategoryChanged();
    void searchTextChanged();
    void countChanged();
    void hiddenAppsChanged();
    void favoriteAppsChanged();
    void recentAppsChanged();
    void maxRecentAppsChanged();
    void sortModeChanged();
    void launchCountsChanged();
    void knownAppsChanged();
    void searchShowsHiddenChanged();
    void showFavoritesOnlyChanged();
    void sortFavoritesAlphabeticallyChanged();
    void useSystemCategoriesChanged();
    void categoriesChanged();
    void groupedByCategoryChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    void recordLaunch(const QString &storageId);
    // Re-run only the filter (Qt-version-bridged invalidateFilter); see .cpp.
    void invalidateFilterCompat();
    void invalidateStorageIdCache();
    void ensureStorageIdCache() const;
    void invalidateHaystackCache();
    [[nodiscard]] QString ensureHaystack(int sourceRow) const;

    // Per-source-row sort inputs, computed once per query and cached, instead
    // of re-read via data() + re-folded inside SearchRanking on every lessThan
    // comparison. Turns the per-keystroke sort from O(N·logN)×(role reads +
    // case-folds) into O(N) fill + O(N·logN) integer/short-string compares.
    struct RowScore {
        QString sid;
        QString name;
        QString category;
        int relevance = SearchRanking::TierNoMatch;
        int launchCount = 0;
        bool isDefault = false; // a mimeapps.list default for some type
        bool isPreferred = false; // a role default (browser/mail/file-mgr/terminal) — ranks above isDefault
    };
    [[nodiscard]] const RowScore &rowScore(const QModelIndex &sourceIndex) const;
    void invalidateRowScoreCache();

    QString m_filterCategory;
    QString m_searchText;
    // Pre-folded copy of m_searchText so filterAcceptsRow can run a
    // case-sensitive contains() against the cached lower-cased haystack
    // and avoid the per-character Unicode case-fold inside QString::contains.
    QString m_searchTextLower;
    // Naive singular form of the query ("games" → "game"), or empty when the
    // query doesn't end in s / is too short. Filter + ranking both consult
    // it so a plural query against a singular category still matches.
    QString m_searchTextLowerSingular;
    int m_maxRecentApps = 6;
    int m_sortMode = Alphabetical;
    int m_iconGeneration = 0;
    QHash<QString, int> m_frecencyScores;
    bool m_searchUsesFrecency = false;
    bool m_searchShowsHidden = false;
    bool m_showFavoritesOnly = false;
    bool m_sortFavoritesAlphabetically = false;
    QSet<QString> m_defaultAppsSet;
    QStringList m_defaultApps;
    // Storage ids of the user's role defaults (default browser / mail / file
    // manager via KApplicationTrader, terminal via kdeglobals). Outrank the
    // broader mimeapps defaults in the search tiebreak.
    QSet<QString> m_preferredAppsSet;

    // Hidden / favorite / recent / known lists, launch counts, and the
    // derived membership sets + favorite-position index consulted by
    // filterAcceptsRow / lessThan.
    LaunchBookkeeping m_book;

    // storageId → source-row cache for getByStorageId(). Built lazily on
    // first call; invalidated when the source model resets or rows shift
    // (KSycoca changes). Mutable because getByStorageId is const.
    mutable QHash<QString, int> m_storageIdToSourceRow;
    mutable bool m_storageIdCacheDirty = true;

    // source-row → lower-cased haystack ("name\ngeneric\nkw1\n…\nsource")
    // used by filterAcceptsRow during search. Built lazily per row on
    // first match attempt; cleared in lockstep with the storage-id cache
    // when the source model changes.
    mutable QHash<int, QString> m_haystackCache;

    // source-row → cached sort inputs (see RowScore). Filled lazily in
    // lessThan(); cleared when any input changes (query, launch counts,
    // default apps, or source-model data).
    mutable QHash<int, RowScore> m_rowScoreCache;

    // Lazy cache for the groupedByCategory Q_PROPERTY. Rebuilds on next
    // read after any filter/visibility change that flips the dirty flag.
    // Skips the O(N) QVariantMap-construction loop when QML isn't actually
    // reading the property (e.g. when in Alphabetical sort and the
    // CategoryGridView binding short-circuits).
    mutable QVariantList m_groupedByCategoryCache;
    mutable bool m_groupedByCategoryDirty = true;
};
