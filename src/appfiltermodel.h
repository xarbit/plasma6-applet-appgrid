/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QVariantMap>

#include <memory>

#include "appranking.h"
#include "approwindex.h"
#include "appsearch.h"
#include "filterproxymodel.h"

/**
 * @brief Proxy model adding search, category filtering, and app hiding.
 *
 * Wraps AppModel and provides QML-bindable properties for live filtering.
 * Also hides/unhides by storageId and returns row data as a QVariantMap.
 * Launching is LaunchService's; recordRecentLaunch() takes its reports.
 */
class LaunchBookkeeping;
class LaunchStateStore;

class AppFilterModel : public FilterProxyModel
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
    Q_PROPERTY(bool showFavoritesOnly READ showFavoritesOnly WRITE setShowFavoritesOnly NOTIFY showFavoritesOnlyChanged)
    Q_PROPERTY(bool sortFavoritesAlphabetically READ sortFavoritesAlphabetically WRITE setSortFavoritesAlphabetically NOTIFY sortFavoritesAlphabeticallyChanged)
    Q_PROPERTY(bool useSystemCategories READ useSystemCategories WRITE setUseSystemCategories NOTIFY useSystemCategoriesChanged)
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
        Alphabetical = AppRanking::Alphabetical,
        MostUsed = AppRanking::MostUsed,
        ByCategory = AppRanking::ByCategory,
    };
    Q_ENUM(SortMode)

    explicit AppFilterModel(QObject *parent = nullptr);
    ~AppFilterModel() override;

    /** Read and change the hidden apps, recents and launch counts in @p state
     *  (not owned). Until one is set the model keeps them in a store of its
     *  own, in memory. */
    void setLaunchState(LaunchStateStore *state);

    [[nodiscard]] QString filterCategory() const;
    void setFilterCategory(const QString &category);

    [[nodiscard]] QString searchText() const;
    void setSearchText(const QString &text);

    /** Set the search text, category filter and favourites-only mode together
     *  in a single proxy pass. A search starting or ending changes all three;
     *  setting them one by one re-filtered up to three times and sent the view
     *  one notification per removed row range. */
    Q_INVOKABLE void setSearchState(const QString &text, const QString &category, bool favoritesOnly);

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

    /** Storage ids currently shown with the "new" badge, computed by
     *  NewAppsTracker (recently installed and unused). */
    void setNewApps(const QSet<QString> &newApps);

    [[nodiscard]] bool showFavoritesOnly() const;
    void setShowFavoritesOnly(bool enabled);

    [[nodiscard]] bool useSystemCategories() const;
    void setUseSystemCategories(bool enabled);

    // A launch happened (LaunchService::appLaunched): prepend to recents
    // (capped) and bump the launch count.
    void recordRecentLaunch(const QString &storageId);

    [[nodiscard]] QStringList defaultApps() const;
    void setDefaultApps(const QStringList &list);
    /** Storage ids of the role defaults (default browser / mail / file
     *  manager / terminal); they outrank the mime defaults in search. */
    void setPreferredApps(const QSet<QString> &apps);

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
    [[nodiscard]] Q_INVOKABLE QStringList nonEmptyCategories() const;
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
    void newAppsChanged();
    void searchShowsHiddenChanged();
    void showFavoritesOnlyChanged();
    void sortFavoritesAlphabeticallyChanged();
    void useSystemCategoriesChanged();
    void categoriesChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    // Drop recents whose app left the database (uninstalled); keeps the recents
    // row from showing dead entries. Runs on every KSycoca reload.
    void pruneRecentsToExisting();

    // Store @p text and its folded forms, and drop the cached relevance.
    void applySearchText(const QString &text);

    QString m_filterCategory;
    AppSearch::Query m_query;
    int m_maxRecentApps = 6;
    int m_sortMode = Alphabetical;
    int m_iconGeneration = 0;
    QSet<QString> m_newApps; // storage ids with the new-app badge (from NewAppsTracker)
    bool m_searchShowsHidden = false;
    bool m_showFavoritesOnly = false;
    bool m_sortFavoritesAlphabetically = false;

    // The hidden apps, recents and launch counts live in the launch state
    // store; the filter and sort read its lookups through book().
    [[nodiscard]] const LaunchBookkeeping &book() const;
    std::unique_ptr<LaunchStateStore> m_ownState;
    QPointer<LaunchStateStore> m_state;
    // The sort order: favourites, default apps, frecency and the cached
    // per-row sort inputs.
    AppRanking m_ranking;

    // The source rows by storage id, and their search haystacks.
    AppRowIndex m_index;
};
