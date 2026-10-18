/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QSet>
#include <QSharedData> // QExplicitlySharedDataPointer (KService::Ptr)
#include <QString>
#include <QStringList>
#include <QVector>

class KService;

/** Data for a single installed application. */
struct AppEntry {
    QString name;
    QString icon;
    QString desktopFile;
    QStringList categories;
    QString genericName;
    QString storageId;
    QStringList keywords;
    QString comment;
    QString installSource;
    // A favourite the XDG menu doesn't list (#224): served for the favourites
    // view only, never in the grid.
    bool outsideMenu = false;
};

/**
 * @brief Flat list model of installed applications.
 *
 * Loads the XDG application menu hierarchy via KServiceGroup and exposes
 * each application with its name, icon, category, and desktop file path.
 */
class AppModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool useSystemCategories READ useSystemCategories WRITE setUseSystemCategories NOTIFY useSystemCategoriesChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        IconRole,
        DesktopFileRole,
        CategoryRole,
        CategoriesRole,
        GenericNameRole,
        StorageIdRole,
        KeywordsRole,
        CommentRole,
        InstallSourceRole,
        OutsideMenuRole,
    };

    explicit AppModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void launch(int index);
    [[nodiscard]] Q_INVOKABLE QStringList categories() const;
    [[nodiscard]] Q_INVOKABLE QString categoryMenuPath(const QString &category) const;
    [[nodiscard]] Q_INVOKABLE QString categoryIcon(const QString &category) const;

    /** detectInstallSource() for @p service. */
    [[nodiscard]] static QString installSourceOf(const QExplicitlySharedDataPointer<KService> &service);

    // Pure helpers — testable without constructing the model.
    /** Where an app comes from: "Web App", "Flatpak", "Snap", "AppImage" or
     *  "System", from its Exec line and its installed .desktop path. */
    [[nodiscard]] static QString detectInstallSource(const QString &exec, const QString &entryPath);
    [[nodiscard]] static QStringList mapCategories(const QStringList &categories);

    [[nodiscard]] bool useSystemCategories() const;
    void setUseSystemCategories(bool enabled);

    /** The favourite storage ids. A favourite the menu doesn't list (an app
     *  with no categories under a menu file without a catch-all, or one the
     *  user removed with the menu editor) is still served, flagged
     *  OutsideMenuRole, so the favourites can show and launch it the way
     *  Kickoff's do (#224). */
    void setFavoriteApps(const QStringList &storageIds);

Q_SIGNALS:
    void useSystemCategoriesChanged();

private Q_SLOTS:
    void reload();

private:
    void loadApplications();
    [[nodiscard]] QStringList favoritesOutsideMenu() const;

    QVector<AppEntry> m_apps;
    QStringList m_categories;
    QHash<QString, QString> m_categoryMenuPaths;
    QHash<QString, QString> m_categoryIcons;
    bool m_useSystemCategories = false;
    // Set once the first load ran; setFavoriteApps() only reloads after that.
    bool m_loaded = false;
    QStringList m_favoriteApps;
    // Storage ids the menu walk listed, and the favourites it left out.
    QSet<QString> m_placed;
    QStringList m_outsideMenu;
};
