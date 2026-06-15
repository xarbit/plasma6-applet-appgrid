/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appmodel.h"

#include "appmodelassembly.h"
#include "categorymapping.h"

#include <KIO/ApplicationLauncherJob>
#include <KJob>
#include <KLocalizedString>
#include <KService>
#include <KServiceGroup>
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
    // Traverse the XDG menu hierarchy via KServiceGroup, emitting one AppEntry
    // per service *occurrence* (an app reachable from several menu groups
    // yields several). The dedup/merge/sort/category-collect is pure — see
    // AppModelAssembly::assemble — so the walk only does KService extraction.
    // In system mode: top-level group captions define categories (respects kmenuedit).
    // In simple mode: the hardcoded mapping table maps desktop categories to clean groups.
    const bool systemMode = m_useSystemCategories;
    QVector<AppEntry> occurrences;

    std::function<void(KServiceGroup::Ptr, const QString &)> walkGroup;
    walkGroup = [&](KServiceGroup::Ptr group, const QString &category) {
        if (!group || !group->isValid()) {
            return;
        }

        const auto entries = group->entries(true /* sorted */, true /* excludeNoDisplay */, false /* allowSeparators */, true /* sortByGenericName */);

        for (const auto &entry : entries) {
            if (entry->isType(KST_KServiceGroup)) {
                auto subGroup = KServiceGroup::Ptr(static_cast<KServiceGroup *>(entry.data()));
                if (!subGroup || !subGroup->isValid() || subGroup->noDisplay()) {
                    continue;
                }

                QString subCategory = category;
                if (systemMode && subCategory.isEmpty()) {
                    subCategory = subGroup->caption();
                    if (subCategory.isEmpty()) {
                        subCategory = subGroup->name();
                    }
                    // Store menu path for kmenuedit (e.g. "Education/")
                    QString relPath = subGroup->relPath();
                    if (relPath.endsWith(QLatin1Char('/'))) {
                        relPath.chop(1);
                    }
                    m_categoryMenuPaths[subCategory] = relPath;
                    // The menu group's own .directory icon is the authoritative
                    // KDE icon for this category; the bar uses it directly.
                    m_categoryIcons[subCategory] = subGroup->icon();
                }
                walkGroup(subGroup, subCategory);
                continue;
            }

            if (!entry->isType(KST_KService)) {
                continue;
            }

            auto service = KService::Ptr(static_cast<KService *>(entry.data()));

            if (!service->isApplication()) {
                continue;
            }
            if (service->noDisplay() || service->exec().isEmpty()) {
                continue;
            }

            const QString storageId = service->storageId();
            if (storageId.isEmpty()) {
                continue;
            }

            AppEntry appEntry;
            appEntry.name = service->name();
            appEntry.icon = service->icon();
            appEntry.desktopFile = service->entryPath();
            appEntry.genericName = service->genericName();
            appEntry.storageId = storageId;
            appEntry.keywords = service->keywords();
            appEntry.comment = service->comment();

            // Detect install source from the exec line and the installed
            // .desktop path. entryPath() is already the resolved absolute path
            // (KService applies XDG precedence), so no QStandardPaths::locate()
            // stat per app is needed — it would just return entryPath() back.
            appEntry.installSource = detectInstallSource(service->exec(), service->entryPath());

            if (systemMode) {
                appEntry.categories.append(category.isEmpty() ? QStringLiteral("Other") : category);
            } else {
                appEntry.categories = mapCategories(service->categories());
            }

            occurrences.append(appEntry);
        }
    };

    walkGroup(KServiceGroup::root(), QString());

    auto assembled = AppModelAssembly::assemble(occurrences, systemMode);
    m_apps = std::move(assembled.apps);
    m_categories = std::move(assembled.categories);

    // Simple mode: the bar shows translated bucket names, so key the icon
    // lookup by the same translated label. (System mode already captured each
    // group's .directory icon during the walk above.)
    if (!systemMode) {
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
