/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "menutree.h" // MenuTree::RawFolder

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QVector>

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
    QString folderRelPath; ///< menu path of the group this occurrence sits in (#201)
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
    };

    explicit AppModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void launch(int index);
    [[nodiscard]] Q_INVOKABLE QStringList categories() const;
    [[nodiscard]] Q_INVOKABLE QString categoryMenuPath(const QString &category) const;
    [[nodiscard]] Q_INVOKABLE QString categoryIcon(const QString &category) const;

    /** Storage ids of every currently installed app, in model order. The
     *  new-app tracker diffs this against its stored baseline. */
    [[nodiscard]] QStringList storageIds() const;

    /** The cached menu scan behind this model — every subgroup and every app
     *  *occurrence* (pre-dedup, each with its folderRelPath). The folder tree
     *  (#201) is built from this, so the menu is walked once for both views.
     *  Refreshed on each reload(); read after the model's first load. */
    [[nodiscard]] const QList<MenuTree::RawFolder> &menuFolders() const
    {
        return m_menuFolders;
    }
    [[nodiscard]] const QVector<AppEntry> &occurrences() const
    {
        return m_occurrences;
    }

    // Pure helpers — testable without constructing the model.
    [[nodiscard]] static QString detectInstallSource(const QString &exec, const QString &resolvedPath);
    [[nodiscard]] static QStringList mapCategories(const QStringList &categories);

    [[nodiscard]] bool useSystemCategories() const;
    void setUseSystemCategories(bool enabled);

Q_SIGNALS:
    void useSystemCategoriesChanged();

private Q_SLOTS:
    void reload();

private:
    void loadApplications();

    QVector<AppEntry> m_apps;
    QStringList m_categories;
    QHash<QString, QString> m_categoryMenuPaths;
    QHash<QString, QString> m_categoryIcons;
    // Cached menu scan (see menuFolders()/occurrences()): the folder tree reads
    // these so the KServiceGroup walk runs once, not once per view.
    QList<MenuTree::RawFolder> m_menuFolders;
    QVector<AppEntry> m_occurrences;
    bool m_useSystemCategories = false;
};
