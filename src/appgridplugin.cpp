/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include <KDesktopFile>
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KRunner/ResultsModel>
#include <KService>
#include <KTerminalLauncherJob>
#include <KWindowEffects>
#include <KWindowSystem>

#include <PlasmaActivities/ResourceInstance>

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif
#ifdef APPGRID_X11_SUPPORT
#include <KX11Extras>
#endif
#include <kcoreaddons_version.h>
#include <LayerShellQt/window.h>
#include <plasma_version.h>
#include <Plasma/Containment>
#include <PlasmaQuick/AppletQuickItem>
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
#include <QXmlStreamReader>
#include <QTimer>
#include <QUrl>
#include <QWindow>

// Known task manager plugin IDs, matching the list used by Kicker.
AppGridPlugin::AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
    : Plasma::Applet(parent, data, args)
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

bool AppGridPlugin::isUniversalBuild() const
{
#ifdef APPGRID_UNIVERSAL_BUILD
    return true;
#else
    return false;
#endif
}

#ifdef APPGRID_UNIVERSAL_BUILD
UpdateChecker *AppGridPlugin::updateChecker() const
{
    if (!m_updateChecker) {
        const QString version = QString::fromUtf8(APPGRID_VERSION);
        m_updateChecker = new UpdateChecker(version, const_cast<AppGridPlugin *>(this));
    }
    return m_updateChecker;
}
#endif

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
    // LayerTop: above normal windows but below OSD popups (like KRunner)
    layer->setLayer(LayerShellQt::Window::LayerTop);
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

void AppGridPlugin::setInputRect(QWindow *window, int x, int y, int w, int h)
{
    if (!window)
        return;

    if (w <= 0 || h <= 0) {
        // Empty region = "remove mask" per Qt docs, restores full-window input.
        window->setMask(QRegion());
        return;
    }
    // On Wayland this maps to wl_surface.set_input_region(rect). Areas outside
    // the rect become pass-through, so events land on the surface below.
    window->setMask(QRegion(QRect(x, y, w, h)));
}

void AppGridPlugin::notifyAppLaunched(const QString &storageId)
{
    if (storageId.isEmpty())
        return;
    // Standard convention used by Kicker, Kickoff and friends: the resource
    // URL is "applications:<storage-id>", tagged with our agent so other
    // tools can attribute the launch to AppGrid.
    KActivities::ResourceInstance::notifyAccessed(
        QUrl(QStringLiteral("applications:") + storageId),
        QStringLiteral("dev.xarbit.appgrid"));
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

bool AppGridPlugin::isDiscoverAvailable() const
{
    return static_cast<bool>(KService::serviceByDesktopName(QStringLiteral("org.kde.discover")));
}

// Maps an AppModel install-source string to the Discover backend name
// that handles it. Returns empty for sources Discover doesn't manage.
static QString backendForSource(const QString &source)
{
    if (source == QLatin1String("System"))  return QStringLiteral("packagekit");
    if (source == QLatin1String("Flatpak")) return QStringLiteral("flatpak");
    if (source == QLatin1String("Snap"))    return QStringLiteral("snap");
    return {};
}

// CLI tool the backend talks to. The plugin .so ships with Discover but
// is non-functional without the tool — return empty for backends that
// don't have an external dependency to verify.
static QString toolForBackend(const QString &backend)
{
    if (backend == QLatin1String("packagekit")) return QStringLiteral("pkcon");
    if (backend == QLatin1String("flatpak"))    return QStringLiteral("flatpak");
    if (backend == QLatin1String("snap"))       return QStringLiteral("snap");
    return {};
}

// True when both the Discover backend plugin and its underlying CLI tool
// are present. Called per right-click context-menu open, so re-resolving
// each time picks up backend installs without a restart and the lookup
// (one libraryPaths scan + one findExecutable) is cheap.
static bool discoverBackendInstalled(const QString &name)
{
    const QString relPath = QStringLiteral("discover/") + name + QStringLiteral("-backend.so");
    bool pluginFound = false;
    for (const auto &dir : QCoreApplication::libraryPaths()) {
        if (QFileInfo::exists(dir + QLatin1Char('/') + relPath)) {
            pluginFound = true;
            break;
        }
    }

    const QString tool = toolForBackend(name);
    return pluginFound
        && (tool.isEmpty() || !QStandardPaths::findExecutable(tool).isEmpty());
}

bool AppGridPlugin::canManageInDiscover(const QString &storageId) const
{
    if (storageId.isEmpty() || !isDiscoverAvailable())
        return false;
    auto service = KService::serviceByStorageId(storageId);
    if (!service)
        return false;
    const auto resolvedPath = QStandardPaths::locate(
        QStandardPaths::ApplicationsLocation, service->entryPath());
    // 1.8.0 ships the menu only for Flatpak — system (PackageKit) and
    // Snap routes hit Discover's multi-backend ambiguity that we can't
    // disambiguate without spawning plasma-discover or pulling in a
    // dedicated AppStream dep. Tracked in #119.
    const auto source = AppModel::detectInstallSource(service->exec(), resolvedPath);
    if (source != QLatin1String("Flatpak"))
        return false;
    return discoverBackendInstalled(QStringLiteral("flatpak"));
}

// --- AppStream component id resolver --------------------------------
// AppStreamQt (AppStream::Pool::componentsById) would be the canonical
// way to do this in-process, but pulling in libappstream-qt for one
// lookup per right-click adds a build + runtime dep across every distro
// package for negligible gain. We read the per-app metainfo XML files
// directly instead — same source data Discover's pool indexes from.
// --------------------------------------------------------------------

// Standard locations for per-app AppStream metainfo files. Covers
// distro-installed metadata + Flatpak's system and user exports.
static QStringList metainfoSearchDirs()
{
    QStringList dirs;
    for (const auto &base : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation)) {
        dirs << base + QStringLiteral("/metainfo");
        dirs << base + QStringLiteral("/appdata");
    }
    dirs << QStringLiteral("/var/lib/flatpak/exports/share/metainfo");
    dirs << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/metainfo");
    return dirs;
}

// Read the <id> element from an AppStream metainfo XML file. Returns
// empty if the file can't be opened or doesn't declare an id.
static QString readIdFromMetainfo(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QXmlStreamReader xml(&f);
    while (!xml.atEnd()) {
        xml.readNext();
        if (xml.isStartElement() && xml.name() == QLatin1String("id"))
            return xml.readElementText().trimmed();
    }
    return {};
}

// Scan known metainfo locations for any file whose basename matches one
// of @p basenames (with either .metainfo.xml or .appdata.xml suffix) and
// return the first <id> found.
static QString scanMetainfoForId(const QStringList &basenames)
{
    static const QStringList suffixes{
        QStringLiteral(".metainfo.xml"),
        QStringLiteral(".appdata.xml"),
    };
    for (const auto &dir : metainfoSearchDirs()) {
        for (const auto &name : basenames) {
            for (const auto &sfx : suffixes) {
                const QString id = readIdFromMetainfo(dir + QLatin1Char('/') + name + sfx);
                if (!id.isEmpty())
                    return id;
            }
        }
    }
    return {};
}

// Resolve the AppStream component id for @p storageId. AppStream's spec
// is inconsistent about the .desktop suffix (legacy keeps it, modern
// strips it); reading each app's metainfo <id> returns whichever form
// that specific component declares. Falls back to the storage id when
// no metainfo file exists. Cached per session.
static QString resolveAppStreamId(const QString &storageId)
{
    static QHash<QString, QString> cache;
    const auto cached = cache.constFind(storageId);
    if (cached != cache.constEnd())
        return *cached;

    QString stripped = storageId;
    if (stripped.endsWith(QLatin1String(".desktop")))
        stripped.chop(8);
    QStringList basenames{storageId};
    if (stripped != storageId)
        basenames << stripped;

    const QString found = scanMetainfoForId(basenames);
    const QString resolved = found.isEmpty() ? storageId : found;
    cache.insert(storageId, resolved);
    return resolved;
}

void AppGridPlugin::openInDiscover(const QString &storageId)
{
    if (storageId.isEmpty() || !isDiscoverAvailable())
        return;

    // Prefer X-AppStream-Component if the .desktop file declares one;
    // otherwise resolve the canonical id by asking AppStream which form
    // (.desktop-suffixed or stripped) it actually has registered.
    QString appId;
    auto service = KService::serviceByStorageId(storageId);
    if (service) {
        KDesktopFile desktopFile(service->entryPath());
        appId = desktopFile.desktopGroup().readEntry("X-AppStream-Component", QString());
    }
    if (appId.isEmpty())
        appId = resolveAppStreamId(storageId);

    // appstream:// is the distro-agnostic entry point — Discover's
    // registered URL handler resolves the component through whichever
    // backend (PackageKit, Flatpak, Fwupd) owns it.
    auto *job = new KIO::OpenUrlJob(QUrl(QStringLiteral("appstream://") + appId));
    job->start();
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

// --- System info ---

QVariantMap AppGridPlugin::systemInfo()
{
    QVariantMap info;
    // APPGRID_VERSION carries the dev-suffix on local builds; metadata.json's
    // version doesn't, so prefer the bake-in to reflect the running binary.
    info[QStringLiteral("appgridVersion")] = QString::fromUtf8(APPGRID_VERSION);
    info[QStringLiteral("plasmaVersion")] = QStringLiteral(PLASMA_VERSION_STRING);
    info[QStringLiteral("kfVersion")] = QStringLiteral(KCOREADDONS_VERSION_STRING);
    info[QStringLiteral("qtVersion")] = QString::fromLatin1(qVersion());
    info[QStringLiteral("sessionType")] = KWindowSystem::isPlatformWayland()
        ? QStringLiteral("Wayland") : QStringLiteral("X11");
    info[QStringLiteral("variant")] = m_useNativeActivation
        ? QStringLiteral("Panel") : QStringLiteral("Center");
    info[QStringLiteral("installType")] = isUniversalBuild()
        ? QStringLiteral("Universal package") : QStringLiteral("Distribution package");

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
        default: return {};
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
        default: return {};
        }
    }
    return {};
}

QHash<int, QByteArray> UnifiedSearchModel::roleNames() const
{
    // Qt calls roleNames() once per delegate role read from QML — across a
    // 20-row search-results view that's ~120 calls per keystroke. Hand back
    // a reference to a static map so we don't allocate a fresh QHash each
    // time. Roles are compile-time constant so the table never changes.
    static const QHash<int, QByteArray> kRoleNames = {
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
    return kRoleNames;
}
