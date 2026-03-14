/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QString>
#include <QVariantMap>
#include <QVector>

/** Data for a single installed application. */
struct AppEntry {
    QString name;
    QString icon;
    QString desktopFile;
    QString category;
    QString genericName;
    QString exec;
    QString storageId;
};

/**
 * @brief Flat list model of installed applications.
 *
 * Loads the XDG application menu hierarchy via KServiceGroup and exposes
 * each application with its name, icon, category, and desktop file path.
 */
class AppModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        IconRole,
        DesktopFileRole,
        CategoryRole,
        GenericNameRole,
        StorageIdRole,
    };

    explicit AppModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void launch(int index);
    Q_INVOKABLE QStringList categories() const;

private slots:
    void reload();

private:
    void loadApplications();
    QString mapCategory(const QStringList &categories) const;

    QVector<AppEntry> m_apps;
    QStringList m_categories;
};

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

public:
    /** Sort modes for the grid view. */
    enum SortMode {
        Alphabetical = 0,
        MostUsed = 1,
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

    Q_INVOKABLE void launch(int proxyIndex);
    Q_INVOKABLE void launchByStorageId(const QString &storageId);
    Q_INVOKABLE QStringList categories() const;
    Q_INVOKABLE QVariantMap get(int proxyRow) const;
    Q_INVOKABLE void hideApp(int proxyIndex);
    Q_INVOKABLE void unhideApp(const QString &storageId);
    Q_INVOKABLE bool isFavorite(const QString &storageId) const;
    Q_INVOKABLE void toggleFavorite(const QString &storageId);
    Q_INVOKABLE bool isRecent(const QString &storageId) const;
    Q_INVOKABLE QVariantMap getByStorageId(const QString &storageId) const;
    Q_INVOKABLE bool isNewApp(const QString &storageId) const;
    Q_INVOKABLE void markAllKnown();
    Q_INVOKABLE int getLaunchCount(const QString &storageId) const;

signals:
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

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    void recordLaunch(const QString &storageId);

    QString m_filterCategory;
    QString m_searchText;
    QStringList m_hiddenApps;
    QStringList m_favoriteApps;
    QStringList m_recentApps;
    int m_maxRecentApps = 6;
    int m_sortMode = Alphabetical;
    QHash<QString, int> m_launchCounts;
    QStringList m_knownApps;
};
