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

/**
 * @brief Proxy model adding search, category filtering, and app hiding.
 *
 * Wraps AppModel and provides QML-bindable properties for live filtering.
 * Also exposes convenience methods to launch apps, hide/unhide by storageId,
 * and retrieve row data as a QVariantMap.
 */
class AppFilterModel : public QSortFilterProxyModel {
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

public:
    /** Sort modes for the grid view. */
    enum SortMode {
        Alphabetical = 0,
        MostUsed = 1,
        ByCategory = 2,
    };
    Q_ENUM(SortMode)

    explicit AppFilterModel(QObject *parent = nullptr);

    QString filterCategory() const;
    void setFilterCategory(const QString &category);

    QString searchText() const;
    void setSearchText(const QString &text);

    int count() const;

    QStringList hiddenApps() const;
    void setHiddenApps(const QStringList &list);

    QStringList favoriteApps() const;
    void setFavoriteApps(const QStringList &list);

    QStringList recentApps() const;
    void setRecentApps(const QStringList &list);

    int maxRecentApps() const;
    void setMaxRecentApps(int max);

    int sortMode() const;
    void setSortMode(int mode);

    QVariantMap launchCountsMap() const;
    void setLaunchCountsMap(const QVariantMap &map);

    QStringList knownApps() const;
    void setKnownApps(const QStringList &list);

    bool showFavoritesOnly() const;
    void setShowFavoritesOnly(bool enabled);

    bool useSystemCategories() const;
    void setUseSystemCategories(bool enabled);

    Q_INVOKABLE void launch(int proxyIndex);
    Q_INVOKABLE void launchByStorageId(const QString &storageId);
    // Bookkeeping side of launch: prepend to recents (capped), bump
    // launch count, add to known. Public so tests can exercise it
    // without triggering KIO::ApplicationLauncherJob.
    Q_INVOKABLE void recordRecentLaunch(const QString &storageId);

    QStringList defaultApps() const;
    void setDefaultApps(const QStringList &list);
    // Load defaults from system + user mimeapps.list and update m_defaultApps.
    Q_INVOKABLE void reloadDefaultApps();

    // Pure parser: extract storage IDs from the [Default Applications]
    // section of a mimeapps.list file. Empty list on missing/invalid file.
    static QStringList parseMimeAppsDefaults(const QString &filePath);
    Q_INVOKABLE QStringList categories() const;
    Q_INVOKABLE QString categoryMenuPath(const QString &category) const;
    Q_INVOKABLE QVariantMap get(int proxyRow) const;
    Q_INVOKABLE void hideApp(int proxyIndex);
    // Hide by storageId — needed for bulk hide where the proxy index of
    // earlier sids in the batch would shift as each hide invalidates the
    // filter. Idempotent: re-hiding an already-hidden sid is a no-op.
    Q_INVOKABLE void hideByStorageId(const QString &storageId);
    Q_INVOKABLE void unhideApp(const QString &storageId);
    Q_INVOKABLE bool isFavorite(const QString &storageId) const;
    Q_INVOKABLE bool isRecent(const QString &storageId) const;

    bool sortFavoritesAlphabetically() const;
    void setSortFavoritesAlphabetically(bool enabled);
    Q_INVOKABLE QVariantMap getByStorageId(const QString &storageId) const;
    Q_INVOKABLE bool isNewApp(const QString &storageId) const;
    Q_INVOKABLE QVariantList appsByCategory() const;
    Q_INVOKABLE QStringList nonEmptyCategories() const;
    Q_INVOKABLE void markAllKnown();
    Q_INVOKABLE int getLaunchCount(const QString &storageId) const;

signals:
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
    void rebuildHiddenSet();
    void rebuildFavoriteSet();
    void rebuildRecentSet();
    void rebuildKnownSet();
    void invalidateStorageIdCache();
    void ensureStorageIdCache() const;

    QString m_filterCategory;
    QString m_searchText;
    QStringList m_hiddenApps;
    QStringList m_favoriteApps;
    QStringList m_recentApps;
    int m_maxRecentApps = 6;
    int m_sortMode = Alphabetical;
    QHash<QString, int> m_launchCounts;
    QStringList m_knownApps;
    bool m_showFavoritesOnly = false;
    bool m_sortFavoritesAlphabetically = false;
    QSet<QString> m_defaultAppsSet;
    QStringList m_defaultApps;

    // Parallel-set lookups for the QStringList membership tests that hit
    // every filterAcceptsRow / lessThan call (N apps × per filter refresh).
    // Kept in sync via setters + the rebuild* helpers.
    QSet<QString> m_hiddenAppsSet;
    QSet<QString> m_favoriteAppsSet;
    QSet<QString> m_recentAppsSet;
    QSet<QString> m_knownAppsSet;
    // Position lookup for favorites sort — O(1) replacement for the
    // QStringList::indexOf calls that made lessThan O(N²) per comparison.
    QHash<QString, int> m_favoritePositions;

    // storageId → source-row cache for getByStorageId(). Built lazily on
    // first call; invalidated when the source model resets or rows shift
    // (KSycoca changes). Mutable because getByStorageId is const.
    mutable QHash<QString, int> m_storageIdToSourceRow;
    mutable bool m_storageIdCacheDirty = true;

    // Lazy cache for the groupedByCategory Q_PROPERTY. Rebuilds on next
    // read after any filter/visibility change that flips the dirty flag.
    // Skips the O(N) QVariantMap-construction loop when QML isn't actually
    // reading the property (e.g. when in Alphabetical sort and the
    // CategoryGridView binding short-circuits).
    mutable QVariantList m_groupedByCategoryCache;
    mutable bool m_groupedByCategoryDirty = true;
};
