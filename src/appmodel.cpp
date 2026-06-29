/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appmodel.h"

#include "appmodelassembly.h"
#include "categorymapping.h"
#include "menuscanner.h"

#include <KIO/ApplicationLauncherJob>
#include <KJob>
#include <KLocalizedString>
#include <KService>
#include <KSycoca>

#include <QTimer>

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    // Defer the .desktop scan out of the constructor so it does not block
    // plasmashell startup. The model is empty only until the first event
    // loop pass — long before the launcher window can be opened.
    QTimer::singleShot(0, this, &AppModel::reload);
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &AppModel::reload);
    // Icon-theme / icon-file refresh (#86, #103) is handled by
    // AppFilterModel::iconGeneration, which the delegates watch to force an
    // in-place reload — see there.
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_apps.size();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_apps.size()) {
        return {};
    }

    const auto &app = m_apps[index.row()];
    switch (role) {
    case NameRole:
        return app.name;
    case IconRole:
        return app.icon;
    case DesktopFileRole:
        return app.desktopFile;
    case CategoryRole:
        return app.categories.isEmpty() ? QString() : app.categories.first();
    case CategoriesRole:
        return app.categories;
    case GenericNameRole:
        return app.genericName;
    case StorageIdRole:
        return app.storageId;
    case KeywordsRole:
        return app.keywords;
    case CommentRole:
        return app.comment;
    case InstallSourceRole:
        return app.installSource;
    default:
        return {};
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {IconRole, "iconName"},
        {DesktopFileRole, "desktopFile"},
        {CategoryRole, "category"},
        {CategoriesRole, "categories"},
        {GenericNameRole, "genericName"},
        {StorageIdRole, "storageId"},
        {KeywordsRole, "keywords"},
        {CommentRole, "comment"},
        {InstallSourceRole, "installSource"},
    };
}

static QString translateCategory(const QString &name)
{
    // Each string must appear literally for xgettext extraction
    if (name == QLatin1String("Utilities")) {
        return i18n("Utilities");
    }
    if (name == QLatin1String("Development")) {
        return i18n("Development");
    }
    if (name == QLatin1String("Graphics")) {
        return i18n("Graphics");
    }
    if (name == QLatin1String("Internet")) {
        return i18n("Internet");
    }
    if (name == QLatin1String("Multimedia")) {
        return i18n("Multimedia");
    }
    if (name == QLatin1String("Office")) {
        return i18n("Office");
    }
    if (name == QLatin1String("Games")) {
        return i18n("Games");
    }
    if (name == QLatin1String("Education")) {
        return i18n("Education");
    }
    if (name == QLatin1String("System")) {
        return i18n("System");
    }
    if (name == QLatin1String("Other")) {
        return i18n("Other");
    }
    return name;
}

QStringList AppModel::mapCategories(const QStringList &categories)
{
    QSet<QString> result;
    for (const auto &cat : categories) {
        const auto bucket = mapCategoryToken(cat);
        if (!bucket.isEmpty()) {
            result.insert(translateCategory(bucket));
        }
    }
    if (result.isEmpty()) {
        result.insert(translateCategory(QStringLiteral("Other")));
    }
    return result.values();
}

QString AppModel::detectInstallSource(const QString &exec, const QString &resolvedPath)
{
    if (exec.contains(QLatin1String("--app=")) || exec.contains(QLatin1String("--app-id="))) {
        return QStringLiteral("Web App");
    }
    if (exec.contains(QLatin1String("flatpak")) || resolvedPath.contains(QLatin1String("flatpak"))) {
        return QStringLiteral("Flatpak");
    }
    if (exec.contains(QLatin1String("/snap/")) || resolvedPath.contains(QLatin1String("snap"))) {
        return QStringLiteral("Snap");
    }
    if (exec.contains(QLatin1String("appimage"), Qt::CaseInsensitive)) {
        return QStringLiteral("AppImage");
    }
    return QStringLiteral("System");
}

bool AppModel::useSystemCategories() const
{
    return m_useSystemCategories;
}

void AppModel::setUseSystemCategories(bool enabled)
{
    if (m_useSystemCategories == enabled) {
        return;
    }
    m_useSystemCategories = enabled;
    Q_EMIT useSystemCategoriesChanged();
    reload();
}

void AppModel::loadApplications()
{
    // One menu walk feeds both the flat list and the folder tree — see
    // MenuScanner. It returns an AppEntry per service occurrence (dedup/merge/
    // sort is pure, AppModelAssembly::assemble) plus every subgroup as a
    // RawFolder (the tree reads m_menuFolders, never re-walks).
    // In system mode: top-level group captions define categories (respects kmenuedit).
    // In simple mode: the hardcoded mapping table maps desktop categories to clean groups.
    const bool systemMode = m_useSystemCategories;

    MenuScanner::RawScan scan = MenuScanner::scan(systemMode);
    m_menuFolders = std::move(scan.folders);
    m_occurrences = std::move(scan.occurrences);

    auto assembled = AppModelAssembly::assemble(m_occurrences, systemMode);
    m_apps = std::move(assembled.apps);
    m_categories = std::move(assembled.categories);

    if (systemMode) {
        // The category label is a top-level group's caption; its menu path and
        // .directory icon come straight from that folder. Top-level folders are
        // the ones one segment deep ("Education/", not "Education/Science/").
        for (const auto &folder : std::as_const(m_menuFolders)) {
            QString relPath = folder.relPath;
            if (relPath.endsWith(QLatin1Char('/'))) {
                relPath.chop(1);
            }
            if (relPath.contains(QLatin1Char('/'))) {
                continue; // not top level
            }
            m_categoryMenuPaths[folder.name] = relPath;
            m_categoryIcons[folder.name] = folder.icon;
        }
    } else {
        // Simple mode: the bar shows translated bucket names, so key the icon
        // lookup by the same translated label.
        const auto &iconMap = bucketIconMap();
        for (auto it = iconMap.cbegin(); it != iconMap.cend(); ++it) {
            m_categoryIcons.insert(translateCategory(it.key()), it.value());
        }
    }
}

void AppModel::launch(int index)
{
    if (index < 0 || index >= m_apps.size()) {
        return;
    }

    const auto &app = m_apps[index];
    auto service = KService::serviceByDesktopPath(app.desktopFile);
    if (!service) {
        service = KService::serviceByDesktopName(app.desktopFile);
    }
    if (!service) {
        return;
    }

    auto *job = new KIO::ApplicationLauncherJob(service);
    job->setAutoDelete(true);
    connect(job, &KJob::finished, this, [](KJob *j) {
        if (j->error()) {
            qWarning() << "AppGrid: failed to launch application:" << j->errorString();
        }
    });
    job->start();
}

QStringList AppModel::categories() const
{
    return m_categories;
}

void AppModel::reload()
{
    // reload() is for app-list changes (KSycoca databaseChanged). Icon-theme /
    // icon-file refresh lives in AppFilterModel::iconGeneration.
    beginResetModel();
    m_apps.clear();
    m_categories.clear();
    m_categoryMenuPaths.clear();
    m_categoryIcons.clear();
    loadApplications();
    endResetModel();
}

QStringList AppModel::storageIds() const
{
    QStringList ids;
    ids.reserve(m_apps.size());
    for (const AppEntry &app : m_apps) {
        ids.append(app.storageId);
    }
    return ids;
}

QString AppModel::categoryMenuPath(const QString &category) const
{
    return m_categoryMenuPaths.value(category);
}

QString AppModel::categoryIcon(const QString &category) const
{
    // A menu group may carry no .directory icon, so guard the empty value too
    // (QHash::value's default only covers an absent key).
    const QString icon = m_categoryIcons.value(category);
    return icon.isEmpty() ? QStringLiteral("applications-other-symbolic") : icon;
}

// AppFilterModel is in appfiltermodel.cpp
