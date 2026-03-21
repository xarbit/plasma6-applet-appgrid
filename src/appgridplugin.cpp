/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KRunner/ResultsModel>
#include <KService>
#include <KTerminalLauncherJob>
#include <KWindowEffects>
#include <KWindowSystem>
#ifdef APPGRID_X11_SUPPORT
#include <KX11Extras>
#endif
#include <kcoreaddons_version.h>
#include <LayerShellQt/window.h>
#include <plasma_version.h>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <algorithm>
#include <QDir>
#include <QCursor>
#include <QGuiApplication>
#include <QFile>
#include <QTextStream>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QWindow>
#include <sessionmanagement.h>

// Known task manager plugin IDs, matching the list used by Kicker.
static constexpr QLatin1StringView s_knownTaskManagers[] = {
    QLatin1StringView("org.kde.plasma.taskmanager"),
    QLatin1StringView("org.kde.plasma.icontasks"),
    QLatin1StringView("org.kde.plasma.expandingiconstaskmanager"),
};

AppGridPlugin::AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : Plasma::Applet(parent, data, args)
    , m_session(new SessionManagement(this))
{
    m_filterModel.setSourceModel(&m_appModel);
    m_runnerModel = new KRunner::ResultsModel(this);
    m_runnerFilterModel.setSourceModel(m_runnerModel);
    m_runnerFilterModel.setAppModel(&m_filterModel);
    m_searchModel.setAppModel(&m_filterModel);
    m_searchModel.setRunnerModel(&m_runnerFilterModel);
    QQuickWindow::setDefaultAlphaBuffer(true);

    // PlasmoidItem::init() connects activated → setExpanded(true).
    // For custom Window mode, we add a second connection (fires after PlasmoidItem's)
    // that immediately reverses the expansion, preventing the native popup from showing.
    // The popup variant (AppGridPopupPlugin) sets m_useNativeActivation = true to skip this.
    QTimer::singleShot(0, this, [this]() {
        if (!m_useNativeActivation) {
            auto *quickItem = PlasmaQuick::AppletQuickItem::itemForApplet(this);
            if (quickItem) {
                connect(this, &Plasma::Applet::activated, this, [quickItem]() {
                    quickItem->setProperty("expanded", false);
                });
            }
        }
    });
}

AppFilterModel *AppGridPlugin::appsModel() const
{
    return const_cast<AppFilterModel *>(&m_filterModel);
}

QAbstractItemModel *AppGridPlugin::runnerModel() const
{
    return const_cast<RunnerFilterModel *>(&m_runnerFilterModel);
}

KRunner::ResultsModel *AppGridPlugin::runnerSourceModel() const
{
    return m_runnerModel;
}

UnifiedSearchModel *AppGridPlugin::searchModel() const
{
    return const_cast<UnifiedSearchModel *>(&m_searchModel);
}

bool AppGridPlugin::isWayland() const
{
    return KWindowSystem::isPlatformWayland();
}

bool AppGridPlugin::runRunnerResult(int index)
{
    if (!m_runnerModel || index < 0 || index >= m_runnerFilterModel.rowCount())
        return false;
    // Map from filter proxy index to source model index
    const auto proxyIdx = m_runnerFilterModel.index(index, 0);
    const auto sourceIdx = m_runnerFilterModel.mapToSource(proxyIdx);
    return m_runnerModel->run(sourceIdx);
}

// --- Window management ---

// -- Screen helpers --

QScreen *AppGridPlugin::screenForCursor() const
{
    const QPoint pos = QCursor::pos();
    for (auto *screen : QGuiApplication::screens()) {
        if (screen->geometry().contains(pos))
            return screen;
    }
    return nullptr;
}

QScreen *AppGridPlugin::screenForPanel() const
{
    int idx = containment() ? containment()->screen() : -1;
    const auto screens = QGuiApplication::screens();
    return (idx >= 0 && idx < screens.size()) ? screens.at(idx) : nullptr;
}

// -- Wayland (LayerShellQt) --

void AppGridPlugin::configureWayland(QWindow *window)
{
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerOverlay);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    layer->setScope(QStringLiteral("appgrid"));
    // Cover the full screen including panel exclusive zones
    layer->setExclusiveZone(-1);
    layer->setAnchors(LayerShellQt::Window::Anchors(
        LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
        | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
}

void AppGridPlugin::updateScreenWayland(QWindow *window, QScreen *target, bool useActiveScreen)
{
    auto *layer = LayerShellQt::Window::get(window);

    // New API (LayerShellQt 6.6+)
    if (layer->metaObject()->indexOfProperty("wantsToBeOnActiveScreen") >= 0) {
        if (useActiveScreen || !target) {
            layer->setProperty("wantsToBeOnActiveScreen", true);
        } else {
            layer->setProperty("wantsToBeOnActiveScreen", false);
            layer->setProperty("screen", QVariant::fromValue(target));
        }
    } else {
        // Old API (LayerShellQt < 6.6) — deprecated but needed for compatibility
        if (target)
            window->setScreen(target);
QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
        layer->setScreenConfiguration(
            useActiveScreen ? LayerShellQt::Window::ScreenFromCompositor
                            : LayerShellQt::Window::ScreenFromQWindow);
QT_WARNING_POP
    }
}

// -- X11 (remove when targeting Plasma 6.8+ Wayland-only) --

#ifdef APPGRID_X11_SUPPORT
void AppGridPlugin::configureX11(QWindow *window)
{
    window->setFlags(window->flags() | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    KX11Extras::setState(window->winId(), NET::SkipTaskbar | NET::SkipPager);
}
#endif

// -- Public API --

void AppGridPlugin::configureWindow(QWindow *window)
{
    if (!window)
        return;

    auto fmt = window->format();
    fmt.setAlphaBufferSize(8);
    window->setFormat(fmt);

    if (KWindowSystem::isPlatformWayland()) {
        configureWayland(window);
    }
#ifdef APPGRID_X11_SUPPORT
    else {
        configureX11(window);
    }
#endif
}

void AppGridPlugin::updateWindowScreen(QWindow *window, bool useActiveScreen)
{
    if (!window || !KWindowSystem::isPlatformWayland())
        return;

    QScreen *target = useActiveScreen ? screenForCursor() : screenForPanel();
    updateScreenWayland(window, target, useActiveScreen);
}

QRect AppGridPlugin::targetScreenGeometry(bool useActiveScreen)
{
    QScreen *target = useActiveScreen ? screenForCursor() : screenForPanel();
    if (!target)
        target = QGuiApplication::primaryScreen();
    return target ? target->geometry() : QRect();
}

void AppGridPlugin::setBlurBehind(QWindow *window, bool enable, int x, int y, int w, int h, int radius)
{
    if (!window)
        return;

    QRegion region;
    if (enable && w > 0 && h > 0) {
        // Build a rounded-rect region by subtracting square corners
        // and adding elliptical arcs.
        const int d = radius * 2;
        QRegion rect(x, y, w, h);

        QRegion corners;
        corners += QRegion(x, y, radius, radius);
        corners += QRegion(x + w - radius, y, radius, radius);
        corners += QRegion(x, y + h - radius, radius, radius);
        corners += QRegion(x + w - radius, y + h - radius, radius, radius);
        rect -= corners;

        rect += QRegion(x, y, d, d, QRegion::Ellipse);
        rect += QRegion(x + w - d, y, d, d, QRegion::Ellipse);
        rect += QRegion(x, y + h - d, d, d, QRegion::Ellipse);
        rect += QRegion(x + w - d, y + h - d, d, d, QRegion::Ellipse);

        region = rect;
    }

    KWindowEffects::enableBlurBehind(window, enable, region);
}

// --- Session actions ---

void AppGridPlugin::sleep()
{
    m_session->suspend();
}

void AppGridPlugin::restart()
{
    m_session->requestReboot();
}

void AppGridPlugin::shutDown()
{
    m_session->requestShutdown();
}

void AppGridPlugin::lock()
{
    m_session->lock();
}

void AppGridPlugin::logOut()
{
    m_session->requestLogout();
}

void AppGridPlugin::switchUser()
{
    m_session->switchUser();
}

// --- Prefix mode commands ---

// Validate that the given shell path is listed in /etc/shells.
// Falls back to /bin/sh if empty or not found.
static QString validatedShell(const QString &shell)
{
    if (shell.isEmpty())
        return QStringLiteral("/bin/sh");

    QFile file(QStringLiteral("/etc/shells"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            const auto line = in.readLine().trimmed();
            if (!line.isEmpty() && !line.startsWith(QLatin1Char('#')) && line == shell)
                return shell;
        }
    }

    qWarning() << "AppGrid: shell not in /etc/shells, falling back to /bin/sh:" << shell;
    return QStringLiteral("/bin/sh");
}

void AppGridPlugin::runInTerminal(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty())
        return;

    const QString sh = validatedShell(shell);

    // Wrap command so the terminal stays open after it finishes.
    const QString wrapped = QStringLiteral("%1 -c '%2; echo; echo \"[Press Enter to close]\"; read _'")
                                .arg(sh, QString(command).replace(QLatin1Char('\''), QStringLiteral("'\"'\"'")));

    auto *job = new KTerminalLauncherJob(wrapped);
    job->start();
}

void AppGridPlugin::runCommand(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty())
        return;

    const QString sh = validatedShell(shell);
    QProcess::startDetached(sh, {QStringLiteral("-c"), command});
}

QStringList AppGridPlugin::availableShells()
{
    QStringList shells;
    QFile file(QStringLiteral("/etc/shells"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            const QString line = in.readLine().trimmed();
            if (!line.isEmpty() && !line.startsWith(QLatin1Char('#')) && QFile::exists(line))
                shells.append(line);
        }
    }
    return shells;
}

QVariantList AppGridPlugin::appActions(const QString &storageId)
{
    QVariantList result;
    auto service = KService::serviceByStorageId(storageId);
    if (!service)
        return result;

    const auto actions = service->actions();
    for (const auto &action : actions) {
        if (action.text().isEmpty())
            continue;
        QVariantMap map;
        map[QStringLiteral("text")] = action.text();
        map[QStringLiteral("icon")] = action.icon();
        map[QStringLiteral("name")] = action.name();
        result.append(map);
    }
    return result;
}

void AppGridPlugin::launchAppAction(const QString &storageId, int actionIndex)
{
    auto service = KService::serviceByStorageId(storageId);
    if (!service)
        return;

    const auto actions = service->actions();
    if (actionIndex < 0 || actionIndex >= actions.size())
        return;

    auto *job = new KIO::ApplicationLauncherJob(actions.at(actionIndex));
    job->start();
}

void AppGridPlugin::openMenuEditor(const QString &menuPath)
{
    QStringList args;
    if (!menuPath.isEmpty())
        args << menuPath;
    QProcess::startDetached(QStringLiteral("kmenuedit"), args);
}

QVariantList AppGridPlugin::listDirectory(const QString &path)
{
    QString expanded = path;
    if (expanded.startsWith(QLatin1Char('~')))
        expanded = QDir::homePath() + expanded.mid(1);

    // Split into directory + filter for partial paths
    QDir dir(expanded);
    QString filter;
    if (!dir.exists()) {
        QFileInfo fi(expanded);
        dir = QDir(fi.path());
        filter = fi.fileName();
        if (!dir.exists())
            return {};
    }

    QVariantList result;
    QMimeDatabase mimeDb;

    dir.setFilter(QDir::AllEntries | QDir::NoDot);
    dir.setSorting(QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);

    const auto entries = dir.entryInfoList();
    for (const auto &entry : entries) {
        if (!filter.isEmpty() && !entry.fileName().contains(filter, Qt::CaseInsensitive))
            continue;

        QVariantMap item;
        item[QStringLiteral("name")] = entry.fileName();
        item[QStringLiteral("path")] = entry.absoluteFilePath();
        item[QStringLiteral("isDir")] = entry.isDir();

        if (entry.isDir()) {
            item[QStringLiteral("icon")] = QStringLiteral("folder");
        } else {
            const auto mime = mimeDb.mimeTypeForFile(entry);
            item[QStringLiteral("icon")] = mime.iconName();
        }

        result.append(item);
        if (result.size() >= 200)
            break;
    }
    return result;
}

void AppGridPlugin::openFile(const QString &filePath)
{
    if (filePath.isEmpty())
        return;

    auto *job = new KIO::OpenUrlJob(QUrl::fromLocalFile(filePath));
    job->start();
}

// --- Desktop integration ---

void AppGridPlugin::editApplication(const QString &desktopFile)
{
    QProcess::startDetached(QStringLiteral("kmenuedit"), {QFileInfo(desktopFile).fileName()});
}

void AppGridPlugin::pinToTaskManager(const QString &storageId)
{
    Plasma::Containment *panel = containment();
    if (!panel)
        return;

    // Find a task manager applet in the panel containment.
    Plasma::Applet *taskManager = nullptr;
    const auto applets = panel->applets();
    for (auto *applet : applets) {
        const auto pluginId = applet->pluginMetaData().pluginId();
        const bool found = std::any_of(std::begin(s_knownTaskManagers), std::end(s_knownTaskManagers),
                                       [&pluginId](const auto &id) { return id == pluginId; });
        if (found) {
            taskManager = applet;
            break;
        }
    }
    if (!taskManager)
        return;

    auto *quickItem = PlasmaQuick::AppletQuickItem::itemForApplet(taskManager);
    if (!quickItem)
        return;

    const QUrl launcherUrl(QStringLiteral("applications:") + storageId);
    QMetaObject::invokeMethod(quickItem, "addLauncher", Q_ARG(QUrl, launcherUrl));
}

void AppGridPlugin::addToDesktop(const QString &desktopFile)
{
    Plasma::Containment *panel = containment();
    if (!panel)
        return;

    Plasma::Corona *corona = panel->corona();
    if (!corona)
        return;

    Plasma::Containment *desktop = corona->containmentForScreen(panel->screen(), QString(), QString());
    if (!desktop)
        return;

    // Resolve to an absolute path if KService returned a relative one.
    QString absPath = desktopFile;
    if (!QFileInfo(absPath).isAbsolute()) {
        const QString resolved = QStandardPaths::locate(
            QStandardPaths::ApplicationsLocation, QFileInfo(desktopFile).fileName());
        if (!resolved.isEmpty())
            absPath = resolved;
    }

    const QStringList provides = desktop->pluginMetaData().value(
        QStringLiteral("X-Plasma-Provides"), QStringList());

    if (provides.contains(QStringLiteral("org.kde.plasma.filemanagement"))) {
        auto *folderItem = PlasmaQuick::AppletQuickItem::itemForApplet(desktop);
        if (folderItem)
            QMetaObject::invokeMethod(folderItem, "addLauncher",
                                      Q_ARG(QVariant, QUrl::fromLocalFile(absPath)));
    } else {
        desktop->createApplet(QStringLiteral("org.kde.plasma.icon"),
                              QVariantList() << QUrl::fromLocalFile(absPath));
    }
}

// --- System info ---

QVariantMap AppGridPlugin::systemInfo()
{
    QVariantMap info;
    info[QStringLiteral("appgridVersion")] = pluginMetaData().version();
    info[QStringLiteral("plasmaVersion")] = QStringLiteral(PLASMA_VERSION_STRING);
    info[QStringLiteral("kfVersion")] = QStringLiteral(KCOREADDONS_VERSION_STRING);
    info[QStringLiteral("qtVersion")] = QString::fromLatin1(qVersion());
    info[QStringLiteral("sessionType")] = KWindowSystem::isPlatformWayland()
        ? QStringLiteral("Wayland") : QStringLiteral("X11");
    info[QStringLiteral("variant")] = m_useNativeActivation
        ? QStringLiteral("Panel") : QStringLiteral("Center");

    // OS info from /etc/os-release
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (osRelease.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&osRelease);
        while (!in.atEnd()) {
            const auto line = in.readLine();
            if (line.startsWith(QLatin1String("PRETTY_NAME="))) {
                auto val = line.mid(12);
                if (val.startsWith('"') && val.endsWith('"'))
                    val = val.mid(1, val.length() - 2);
                info[QStringLiteral("os")] = val;
                break;
            }
        }
    }

    // Screen info
    const auto screens = QGuiApplication::screens();
    QStringList screenList;
    for (auto *screen : screens) {
        auto geo = screen->geometry();
        screenList.append(QStringLiteral("%1 (%2x%3 @ %4x)")
            .arg(screen->name())
            .arg(geo.width()).arg(geo.height())
            .arg(screen->devicePixelRatio()));
    }
    info[QStringLiteral("screens")] = screenList.join(QStringLiteral(", "));

    return info;
}

QVariantMap UnifiedSearchModel::get(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= rowCount()) return map;
    const auto idx = index(row, 0);
    const auto roles = roleNames();
    for (auto it = roles.begin(); it != roles.end(); ++it)
        map[QString::fromLatin1(it.value())] = data(idx, it.key());
    return map;
}

// --- RunnerFilterModel ---

RunnerFilterModel::RunnerFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

void RunnerFilterModel::setAppModel(AppFilterModel *model)
{
    m_appModel = model;
    // Re-filter when app search results change
    connect(m_appModel, &QAbstractItemModel::modelReset, this, &RunnerFilterModel::invalidate);
    connect(m_appModel, &QAbstractItemModel::layoutChanged, this, &RunnerFilterModel::invalidate);
}

bool RunnerFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!m_appModel)
        return true;

    const auto idx = sourceModel()->index(sourceRow, 0, sourceParent);
    const auto runnerName = idx.data(Qt::DisplayRole).toString();

    // Check if any visible app result has the same name
    for (int i = 0; i < m_appModel->rowCount(); ++i) {
        const auto appIdx = m_appModel->index(i, 0);
        if (appIdx.data(AppModel::NameRole).toString().compare(runnerName, Qt::CaseInsensitive) == 0)
            return false;
    }
    return true;
}

// --- UnifiedSearchModel ---

UnifiedSearchModel::UnifiedSearchModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void UnifiedSearchModel::setAppModel(AppFilterModel *model)
{
    m_appModel = model;
    connect(model, &QAbstractItemModel::modelReset, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::layoutChanged, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsInserted, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsRemoved, this, &UnifiedSearchModel::onSourceChanged);
}

void UnifiedSearchModel::setRunnerModel(RunnerFilterModel *model)
{
    m_runnerModel = model;
    connect(model, &QAbstractItemModel::modelReset, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::layoutChanged, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsInserted, this, &UnifiedSearchModel::onSourceChanged);
    connect(model, &QAbstractItemModel::rowsRemoved, this, &UnifiedSearchModel::onSourceChanged);

    const auto roles = model->roleNames();
    for (auto it = roles.begin(); it != roles.end(); ++it) {
        if (it.value() == "subtext") m_runnerSubtextRole = it.key();
        if (it.value() == "category") m_runnerCategoryRole = it.key();
        if (it.value() == "urls") m_runnerUrlsRole = it.key();
    }
}

void UnifiedSearchModel::onSourceChanged()
{
    if (!m_resetPending) {
        m_resetPending = true;
        QMetaObject::invokeMethod(this, &UnifiedSearchModel::doReset, Qt::QueuedConnection);
    }
}

void UnifiedSearchModel::doReset()
{
    m_resetPending = false;
    beginResetModel();
    endResetModel();
}

int UnifiedSearchModel::appResultCount() const
{
    return m_appModel ? m_appModel->rowCount() : 0;
}

int UnifiedSearchModel::runnerResultCount() const
{
    return m_runnerModel ? m_runnerModel->rowCount() : 0;
}

int UnifiedSearchModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return appResultCount() + runnerResultCount();
}

QVariant UnifiedSearchModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= rowCount())
        return {};
    if (!m_appModel || !m_runnerModel)
        return {};

    const int row = index.row();
    const int ac = appResultCount();
    const bool isApp = row < ac;

    switch (role) {
    case ResultTypeRole:
        return isApp ? QStringLiteral("app") : QStringLiteral("runner");
    case IsSectionBoundaryRole:
        return !isApp && row == ac && ac > 0;
    case ShortcutNumberRole:
        return (row < 9) ? row + 1 : 0;
    case SourceIndexRole:
        return isApp ? row : (row - ac);
    default:
        break;
    }

    if (isApp) {
        const auto srcIdx = m_appModel->index(row, 0);
        switch (role) {
        case NameRole:        return srcIdx.data(AppModel::NameRole);
        case IconRole:        return srcIdx.data(AppModel::IconRole);
        case SubtextRole: {
            auto comment = srcIdx.data(AppModel::CommentRole).toString();
            return comment.isEmpty() ? srcIdx.data(AppModel::GenericNameRole) : comment;
        }
        case CategoryRole:    return srcIdx.data(AppModel::CategoryRole);
        case StorageIdRole:   return srcIdx.data(AppModel::StorageIdRole);
        case DesktopFileRole: return srcIdx.data(AppModel::DesktopFileRole);
        case IsNewRole:       return m_appModel->isNewApp(srcIdx.data(AppModel::StorageIdRole).toString());
        case InstallSourceRole: return srcIdx.data(AppModel::InstallSourceRole);
        }
    } else {
        const int runnerRow = row - ac;
        const auto srcIdx = m_runnerModel->index(runnerRow, 0);
        switch (role) {
        case NameRole:        return srcIdx.data(Qt::DisplayRole);
        case IconRole:        return srcIdx.data(Qt::DecorationRole);
        case SubtextRole:     return m_runnerSubtextRole >= 0 ? srcIdx.data(m_runnerSubtextRole) : QVariant();
        case CategoryRole:    return m_runnerCategoryRole >= 0 ? srcIdx.data(m_runnerCategoryRole) : QVariant();
        case StorageIdRole:
        case DesktopFileRole: {
            if (m_runnerUrlsRole < 0) return QString();
            const auto urls = srcIdx.data(m_runnerUrlsRole).value<QList<QUrl>>();
            for (const auto &url : urls) {
                const auto path = url.toLocalFile();
                if (path.endsWith(QLatin1String(".desktop"))) {
                    if (role == StorageIdRole)
                        return QFileInfo(path).fileName();
                    return path;
                }
            }
            return QString();
        }
        case IsNewRole:       return false;
        case InstallSourceRole: return QString();
        }
    }
    return {};
}

QHash<int, QByteArray> UnifiedSearchModel::roleNames() const
{
    return {
        {ResultTypeRole, "resultType"},
        {NameRole, "name"},
        {IconRole, "iconName"},
        {SubtextRole, "subtext"},
        {CategoryRole, "category"},
        {StorageIdRole, "storageId"},
        {DesktopFileRole, "desktopFile"},
        {IsNewRole, "isNew"},
        {ShortcutNumberRole, "shortcutNumber"},
        {IsSectionBoundaryRole, "isSectionBoundary"},
        {SourceIndexRole, "sourceIndex"},
        {InstallSourceRole, "installSource"},
    };
}
