/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appmodel.h"

#include <KIconLoader>
#include <KLocalizedString>
#include <KService>
#include <KServiceGroup>
#include <KSycoca>

#include <KIO/ApplicationLauncherJob>
#include <KJob>

#include <QIcon>

#include <QStandardPaths>
#include <QTimer>

#include <QCollator>
#include <algorithm>

// Simplified category mapping — maps freedesktop categories to clean groups
static const QHash<QString, QString> &categoryMap()
{
    static const QHash<QString, QString> map = {
        // Utilities
        {QStringLiteral("Utility"), QStringLiteral("Utilities")},
        {QStringLiteral("Accessibility"), QStringLiteral("Utilities")},
        {QStringLiteral("Core"), QStringLiteral("Utilities")},
        {QStringLiteral("Legacy"), QStringLiteral("Utilities")},
        {QStringLiteral("Tools"), QStringLiteral("Utilities")},
        {QStringLiteral("TextEditor"), QStringLiteral("Utilities")},
        {QStringLiteral("TextTools"), QStringLiteral("Utilities")},
        {QStringLiteral("Archiving"), QStringLiteral("Utilities")},
        {QStringLiteral("Compression"), QStringLiteral("Utilities")},
        {QStringLiteral("FileManager"), QStringLiteral("Utilities")},
        {QStringLiteral("TerminalEmulator"), QStringLiteral("Utilities")},
        {QStringLiteral("FileTools"), QStringLiteral("Utilities")},
        {QStringLiteral("Filesystem"), QStringLiteral("Utilities")},
        {QStringLiteral("Calculator"), QStringLiteral("Utilities")},
        {QStringLiteral("Clock"), QStringLiteral("Utilities")},
        {QStringLiteral("ConsoleOnly"), QStringLiteral("Utilities")},
        {QStringLiteral("DiscBurning"), QStringLiteral("Utilities")},
        {QStringLiteral("Viewer"), QStringLiteral("Utilities")},
        // Development
        {QStringLiteral("Development"), QStringLiteral("Development")},
        {QStringLiteral("IDE"), QStringLiteral("Development")},
        {QStringLiteral("Debugger"), QStringLiteral("Development")},
        {QStringLiteral("RevisionControl"), QStringLiteral("Development")},
        {QStringLiteral("WebDevelopment"), QStringLiteral("Development")},
        {QStringLiteral("Building"), QStringLiteral("Development")},
        {QStringLiteral("Translation"), QStringLiteral("Development")},
        {QStringLiteral("GUIDesigner"), QStringLiteral("Development")},
        {QStringLiteral("Profiling"), QStringLiteral("Development")},
        // Graphics
        {QStringLiteral("Graphics"), QStringLiteral("Graphics")},
        {QStringLiteral("2DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("3DGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("RasterGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("VectorGraphics"), QStringLiteral("Graphics")},
        {QStringLiteral("Photography"), QStringLiteral("Graphics")},
        {QStringLiteral("ImageProcessing"), QStringLiteral("Graphics")},
        {QStringLiteral("Scanning"), QStringLiteral("Graphics")},
        {QStringLiteral("OCR"), QStringLiteral("Graphics")},
        {QStringLiteral("Publishing"), QStringLiteral("Graphics")},
        {QStringLiteral("Art"), QStringLiteral("Graphics")},
        // Internet
        {QStringLiteral("Network"), QStringLiteral("Internet")},
        {QStringLiteral("WebBrowser"), QStringLiteral("Internet")},
        {QStringLiteral("Email"), QStringLiteral("Internet")},
        {QStringLiteral("Chat"), QStringLiteral("Internet")},
        {QStringLiteral("InstantMessaging"), QStringLiteral("Internet")},
        {QStringLiteral("IRCClient"), QStringLiteral("Internet")},
        {QStringLiteral("FileTransfer"), QStringLiteral("Internet")},
        {QStringLiteral("P2P"), QStringLiteral("Internet")},
        {QStringLiteral("RemoteAccess"), QStringLiteral("Internet")},
        {QStringLiteral("News"), QStringLiteral("Internet")},
        {QStringLiteral("Feed"), QStringLiteral("Internet")},
        {QStringLiteral("Telephony"), QStringLiteral("Internet")},
        {QStringLiteral("VideoConference"), QStringLiteral("Internet")},
        // Multimedia
        {QStringLiteral("AudioVideo"), QStringLiteral("Multimedia")},
        {QStringLiteral("Audio"), QStringLiteral("Multimedia")},
        {QStringLiteral("Video"), QStringLiteral("Multimedia")},
        {QStringLiteral("Music"), QStringLiteral("Multimedia")},
        {QStringLiteral("Player"), QStringLiteral("Multimedia")},
        {QStringLiteral("Recorder"), QStringLiteral("Multimedia")},
        {QStringLiteral("Midi"), QStringLiteral("Multimedia")},
        {QStringLiteral("Mixer"), QStringLiteral("Multimedia")},
        {QStringLiteral("Sequencer"), QStringLiteral("Multimedia")},
        {QStringLiteral("TV"), QStringLiteral("Multimedia")},
        {QStringLiteral("Tuner"), QStringLiteral("Multimedia")},
        {QStringLiteral("DiscBurning"), QStringLiteral("Multimedia")},
        // Office
        {QStringLiteral("Office"), QStringLiteral("Office")},
        {QStringLiteral("Calendar"), QStringLiteral("Office")},
        {QStringLiteral("ContactManagement"), QStringLiteral("Office")},
        {QStringLiteral("Database"), QStringLiteral("Office")},
        {QStringLiteral("Dictionary"), QStringLiteral("Office")},
        {QStringLiteral("Finance"), QStringLiteral("Office")},
        {QStringLiteral("Presentation"), QStringLiteral("Office")},
        {QStringLiteral("ProjectManagement"), QStringLiteral("Office")},
        {QStringLiteral("Spreadsheet"), QStringLiteral("Office")},
        {QStringLiteral("WordProcessor"), QStringLiteral("Office")},
        {QStringLiteral("Documentation"), QStringLiteral("Office")},
        {QStringLiteral("Chart"), QStringLiteral("Office")},
        {QStringLiteral("FlowChart"), QStringLiteral("Office")},
        // Games
        {QStringLiteral("Game"), QStringLiteral("Games")},
        {QStringLiteral("ActionGame"), QStringLiteral("Games")},
        {QStringLiteral("AdventureGame"), QStringLiteral("Games")},
        {QStringLiteral("ArcadeGame"), QStringLiteral("Games")},
        {QStringLiteral("BoardGame"), QStringLiteral("Games")},
        {QStringLiteral("BlocksGame"), QStringLiteral("Games")},
        {QStringLiteral("CardGame"), QStringLiteral("Games")},
        {QStringLiteral("LogicGame"), QStringLiteral("Games")},
        {QStringLiteral("Simulation"), QStringLiteral("Games")},
        {QStringLiteral("SportsGame"), QStringLiteral("Games")},
        {QStringLiteral("StrategyGame"), QStringLiteral("Games")},
        {QStringLiteral("RolePlaying"), QStringLiteral("Games")},
        {QStringLiteral("Emulator"), QStringLiteral("Games")},
        {QStringLiteral("KidsGame"), QStringLiteral("Games")},
        // Education & Science
        {QStringLiteral("Education"), QStringLiteral("Education")},
        {QStringLiteral("Science"), QStringLiteral("Education")},
        {QStringLiteral("Math"), QStringLiteral("Education")},
        {QStringLiteral("Astronomy"), QStringLiteral("Education")},
        {QStringLiteral("Chemistry"), QStringLiteral("Education")},
        {QStringLiteral("Geography"), QStringLiteral("Education")},
        {QStringLiteral("Languages"), QStringLiteral("Education")},
        {QStringLiteral("Engineering"), QStringLiteral("Education")},
        {QStringLiteral("Physics"), QStringLiteral("Education")},
        {QStringLiteral("Biology"), QStringLiteral("Education")},
        {QStringLiteral("Geology"), QStringLiteral("Education")},
        {QStringLiteral("Electronics"), QStringLiteral("Education")},
        {QStringLiteral("Robotics"), QStringLiteral("Education")},
        {QStringLiteral("DataVisualization"), QStringLiteral("Education")},
        {QStringLiteral("Economy"), QStringLiteral("Education")},
        {QStringLiteral("Electricity"), QStringLiteral("Education")},
        {QStringLiteral("History"), QStringLiteral("Education")},
        {QStringLiteral("Literature"), QStringLiteral("Education")},
        {QStringLiteral("Construction"), QStringLiteral("Education")},
        // System
        {QStringLiteral("System"), QStringLiteral("System")},
        {QStringLiteral("Settings"), QStringLiteral("System")},
        {QStringLiteral("Monitor"), QStringLiteral("System")},
        {QStringLiteral("Security"), QStringLiteral("System")},
        {QStringLiteral("PackageManager"), QStringLiteral("System")},
        {QStringLiteral("HardwareSettings"), QStringLiteral("System")},
        {QStringLiteral("Printing"), QStringLiteral("System")},
        {QStringLiteral("Emulator"), QStringLiteral("System")},
        {QStringLiteral("Virtualization"), QStringLiteral("System")},
    };
    return map;
}

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    // Defer the .desktop scan out of the constructor so it does not block
    // plasmashell startup. The model is empty only until the first event
    // loop pass — long before the launcher window can be opened.
    QTimer::singleShot(0, this, &AppModel::reload);
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &AppModel::reload);
    // Refresh delegate icons on either:
    //   * #86 — icon file replaced on disk (menu editor, package upgrade
    //     touching /usr/share/icons/...). KIconLoader::emitChange() fires
    //     iconChanged after flushing its own caches.
    //   * #103 — user switches icon theme in System Settings → Icons.
    //     The KCM emits iconChanged via the same signal.
    // We re-emit dataChanged on IconRole so Kirigami.Icon delegates
    // re-resolve via the now-fresh pixmap cache. Replaces the older
    // QIcon::setThemeName(QIcon::themeName()) trick that fixed #86 by
    // setting a global theme-name override on Qt's icon engine — which
    // blocked subsequent system theme changes from propagating (#103).
    connect(KIconLoader::global(), &KIconLoader::iconChanged, this, [this]() {
        if (m_apps.isEmpty())
            return;
        emit dataChanged(index(0, 0), index(m_apps.size() - 1, 0), {IconRole});
    });
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_apps.size();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_apps.size())
        return {};

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
    if (name == QLatin1String("Utilities"))   return i18nd("dev.xarbit.appgrid", "Utilities");
    if (name == QLatin1String("Development")) return i18nd("dev.xarbit.appgrid", "Development");
    if (name == QLatin1String("Graphics"))    return i18nd("dev.xarbit.appgrid", "Graphics");
    if (name == QLatin1String("Internet"))    return i18nd("dev.xarbit.appgrid", "Internet");
    if (name == QLatin1String("Multimedia"))  return i18nd("dev.xarbit.appgrid", "Multimedia");
    if (name == QLatin1String("Office"))      return i18nd("dev.xarbit.appgrid", "Office");
    if (name == QLatin1String("Games"))       return i18nd("dev.xarbit.appgrid", "Games");
    if (name == QLatin1String("Education"))   return i18nd("dev.xarbit.appgrid", "Education");
    if (name == QLatin1String("System"))      return i18nd("dev.xarbit.appgrid", "System");
    if (name == QLatin1String("Other"))       return i18nd("dev.xarbit.appgrid", "Other");
    return name;
}

QStringList AppModel::mapCategories(const QStringList &categories)
{
    const auto &map = categoryMap();
    QSet<QString> result;
    for (const auto &cat : categories) {
        auto it = map.find(cat);
        if (it != map.end())
            result.insert(translateCategory(it.value()));
    }
    if (result.isEmpty())
        result.insert(translateCategory(QStringLiteral("Other")));
    return result.values();
}

QString AppModel::detectInstallSource(const QString &exec, const QString &resolvedPath)
{
    if (exec.contains(QLatin1String("--app=")) || exec.contains(QLatin1String("--app-id=")))
        return QStringLiteral("Web App");
    if (exec.contains(QLatin1String("flatpak")) || resolvedPath.contains(QLatin1String("flatpak")))
        return QStringLiteral("Flatpak");
    if (exec.contains(QLatin1String("/snap/")) || resolvedPath.contains(QLatin1String("snap")))
        return QStringLiteral("Snap");
    if (exec.contains(QLatin1String("appimage"), Qt::CaseInsensitive))
        return QStringLiteral("AppImage");
    return QStringLiteral("System");
}

bool AppModel::useSystemCategories() const
{
    return m_useSystemCategories;
}

void AppModel::setUseSystemCategories(bool enabled)
{
    if (m_useSystemCategories == enabled)
        return;
    m_useSystemCategories = enabled;
    emit useSystemCategoriesChanged();
    reload();
}

void AppModel::loadApplications()
{
    QSet<QString> seen;
    // Index storageId → m_apps row for O(1) "merge category into existing
    // entry" lookups when an app appears in multiple menu groups (system
    // categories mode). Without this the merge loop scans m_apps linearly
    // for each duplicate hit — quadratic on large + heavily-categorized
    // installs (Office;Calendar;Documentation, etc.).
    QHash<QString, int> seenIndex;
    QSet<QString> categorySet;

    // Traverse the XDG menu hierarchy via KServiceGroup.
    // In system mode: top-level group captions define categories (respects kmenuedit).
    // In simple mode: the hardcoded mapping table maps desktop categories to clean groups.
    const bool systemMode = m_useSystemCategories;

    std::function<void(KServiceGroup::Ptr, const QString &)> walkGroup;
    walkGroup = [&](KServiceGroup::Ptr group, const QString &category) {
        if (!group || !group->isValid())
            return;

        const auto entries = group->entries(true /* sorted */,
                                            true /* excludeNoDisplay */,
                                            false /* allowSeparators */,
                                            true /* sortByGenericName */);

        for (const auto &entry : entries) {
            if (entry->isType(KST_KServiceGroup)) {
                auto subGroup = KServiceGroup::Ptr(static_cast<KServiceGroup *>(entry.data()));
                if (!subGroup || !subGroup->isValid() || subGroup->noDisplay())
                    continue;

                QString subCategory = category;
                if (systemMode && subCategory.isEmpty()) {
                    subCategory = subGroup->caption();
                    if (subCategory.isEmpty())
                        subCategory = subGroup->name();
                    // Store menu path for kmenuedit (e.g. "Education/")
                    QString relPath = subGroup->relPath();
                    if (relPath.endsWith(QLatin1Char('/')))
                        relPath.chop(1);
                    m_categoryMenuPaths[subCategory] = relPath;
                }
                walkGroup(subGroup, subCategory);
                continue;
            }

            if (!entry->isType(KST_KService))
                continue;

            auto service = KService::Ptr(static_cast<KService *>(entry.data()));

            if (!service->isApplication())
                continue;
            if (service->noDisplay() || service->exec().isEmpty())
                continue;

            const QString storageId = service->storageId();
            if (storageId.isEmpty())
                continue;

            // In system mode, an app can appear in multiple menu groups.
            // Add the new category to the existing entry instead of duplicating.
            if (seen.contains(storageId)) {
                if (systemMode) {
                    auto cat = category.isEmpty() ? QStringLiteral("Other") : category;
                    const int existingIdx = seenIndex.value(storageId, -1);
                    if (existingIdx >= 0) {
                        auto &existing = m_apps[existingIdx];
                        if (!existing.categories.contains(cat)) {
                            existing.categories.append(cat);
                            categorySet.insert(cat);
                        }
                    }
                }
                continue;
            }
            seen.insert(storageId);

            const QString name = service->name();
            if (name.isEmpty())
                continue;

            AppEntry appEntry;
            appEntry.name = name;
            appEntry.icon = service->icon();
            appEntry.desktopFile = service->entryPath();
            appEntry.genericName = service->genericName();
            appEntry.storageId = storageId;
            appEntry.keywords = service->keywords();
            appEntry.comment = service->comment();

            // Detect install source from exec line and resolved path
            const auto exec = service->exec();
            const auto resolvedPath = QStandardPaths::locate(
                QStandardPaths::ApplicationsLocation, service->entryPath());
            appEntry.installSource = detectInstallSource(exec, resolvedPath);

            if (systemMode) {
                auto cat = category.isEmpty() ? QStringLiteral("Other") : category;
                appEntry.categories.append(cat);
            } else {
                appEntry.categories = mapCategories(service->categories());
            }

            for (const auto &cat : std::as_const(appEntry.categories))
                categorySet.insert(cat);
            seenIndex.insert(storageId, m_apps.size());
            m_apps.append(appEntry);
        }
    };

    walkGroup(KServiceGroup::root(), QString());

    // Sort alphabetically
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(m_apps.begin(), m_apps.end(), [&collator](const AppEntry &a, const AppEntry &b) {
        return collator.compare(a.name, b.name) < 0;
    });

    m_categories = categorySet.values();
    m_categories.sort();
}

void AppModel::launch(int index)
{
    if (index < 0 || index >= m_apps.size())
        return;

    const auto &app = m_apps[index];
    auto service = KService::serviceByDesktopPath(app.desktopFile);
    if (!service)
        service = KService::serviceByDesktopName(app.desktopFile);
    if (!service)
        return;

    auto *job = new KIO::ApplicationLauncherJob(service);
    job->setAutoDelete(true);
    connect(job, &KJob::finished, this, [](KJob *j) {
        if (j->error())
            qWarning() << "AppGrid: failed to launch application:" << j->errorString();
    });
    job->start();
}

QStringList AppModel::categories() const
{
    return m_categories;
}

void AppModel::reload()
{
    // Cache-busting for icon changes lives in the constructor's
    // KIconLoader::iconChanged hookup, not here — reload() is for app-list
    // changes (KSycoca databaseChanged). See ctor + issues #86 / #103 for
    // why we dropped the older QIcon::setThemeName trick.
    beginResetModel();
    m_apps.clear();
    m_categories.clear();
    m_categoryMenuPaths.clear();
    loadApplications();
    endResetModel();
}

QString AppModel::categoryMenuPath(const QString &category) const
{
    return m_categoryMenuPaths.value(category);
}

// AppFilterModel is in appfiltermodel.cpp
