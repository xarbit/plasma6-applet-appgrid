/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridcontroller.h"

#include "appgridconstants.h"
#include "appstreamresolver.h"
#include "discoverbackends.h"
#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KDesktopFile>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CommandLauncherJob>
#include <KIO/OpenUrlJob>
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/ResultsModel>
#include <KService>
#include <KTerminalLauncherJob>
#include <KWindowSystem>
#include <QIcon>

#include <PlasmaActivities/ResourceInstance>

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif
#ifdef APPGRID_X11_SUPPORT
#include <KX11Extras>
#endif
#include <LayerShellQt/window.h>
#include <QCursor>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMargins>
#include <QProcess>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QUrl>
#include <QWindow>
#include <kcoreaddons_version.h>
#include <plasma_version.h>

AppGridController::AppGridController(QObject *parent)
    : QObject(parent)
{
    m_filterModel.setSourceModel(&m_appModel);
    m_runnerModel = new KRunner::ResultsModel(this);
    m_runnerFilterModel.setSourceModel(m_runnerModel);
    m_runnerFilterModel.setAppModel(&m_filterModel);
    m_searchModel.setAppModel(&m_filterModel);
    m_searchModel.setRunnerModel(&m_runnerFilterModel);

    // Order runner results by the user's configured plugin arrangement
    // (krunnerrc [Plugins][Favorites]), the same way KRunner/Kickoff do, and
    // keep it in sync when that config changes (#180). The watcher reparses the
    // shared config before emitting, so re-reading it picks up the change.
    m_krunnerConfig = KSharedConfig::openConfig(QStringLiteral("krunnerrc"));
    applyRunnerFavorites();
    m_krunnerWatcher = KConfigWatcher::create(m_krunnerConfig);
    connect(m_krunnerWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &, const QByteArrayList &) {
        applyRunnerFavorites();
    });

    // The FrecencyProvider stays dormant until QML opts in (the search-bias
    // toggle). When active, every refresh of the KAStats ranking forwards
    // directly into the filter model's tiebreak input.
    connect(&m_frecencyProvider, &FrecencyProvider::scoresChanged, this, [this]() {
        m_filterModel.setFrecencyScores(m_frecencyProvider.scores());
    });
    QQuickWindow::setDefaultAlphaBuffer(true);

    // Warm the AppStream pool in the background now, so the first right-click
    // "Manage in Discover" check never blocks on a synchronous metadata parse.
    AppStreamResolver::warm();
}

void AppGridController::setLayerScope(const QString &scope)
{
    m_layerScope = scope;
}

AppFilterModel *AppGridController::appsModel() const
{
    return const_cast<AppFilterModel *>(&m_filterModel);
}

QAbstractItemModel *AppGridController::runnerModel() const
{
    return const_cast<RunnerFilterModel *>(&m_runnerFilterModel);
}

QObject *AppGridController::runnerSourceModel() const
{
    return m_runnerModel;
}

void AppGridController::applyRunnerFavorites()
{
    if (m_runnerModel) {
        m_runnerModel->setFavoriteIds(PluginHelpers::readRunnerFavorites(m_krunnerConfig));
    }
}

UnifiedSearchModel *AppGridController::searchModel() const
{
    return const_cast<UnifiedSearchModel *>(&m_searchModel);
}

bool AppGridController::isWayland() const
{
    return KWindowSystem::isPlatformWayland();
}

bool AppGridController::isUniversalBuild() const
{
#ifdef APPGRID_UNIVERSAL_BUILD
    return true;
#else
    return false;
#endif
}

#ifdef APPGRID_UNIVERSAL_BUILD
UpdateChecker *AppGridController::updateChecker() const
{
    if (!m_updateChecker) {
        const QString version = QString::fromUtf8(APPGRID_VERSION);
        m_updateChecker = new UpdateChecker(version, const_cast<AppGridController *>(this));
    }
    return m_updateChecker;
}
#endif

QModelIndex AppGridController::runnerSourceIndex(int proxyIndex) const
{
    if (!m_runnerModel || proxyIndex < 0 || proxyIndex >= m_runnerFilterModel.rowCount()) {
        return {};
    }
    return m_runnerFilterModel.mapToSource(m_runnerFilterModel.index(proxyIndex, 0));
}

bool AppGridController::runRunnerResult(int index)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->run(sourceIdx);
}

bool AppGridController::runRunnerAction(int index, int actionIndex)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->runAction(sourceIdx, actionIndex);
}

QString AppGridController::runnerSubstitutionText(int index)
{
    const auto sourceIdx = runnerSourceIndex(index);
    if (!sourceIdx.isValid()) {
        return {};
    }
    // calculator is the only KRunner plugin where "keep iterating the
    // expression" beats "run and close". Extend the list as other in-place
    // runners earn their place.
    const auto match = m_runnerModel->getQueryMatch(sourceIdx);
    if (!match.runner() || match.runner()->id() != QLatin1String("calculator")) {
        return {};
    }
    return match.text();
}

// --- Window management ---

// -- Screen helpers --

QScreen *AppGridController::screenForCursor() const
{
    const QPoint pos = QCursor::pos();
    for (auto *screen : QGuiApplication::screens()) {
        if (screen->geometry().contains(pos)) {
            return screen;
        }
    }
    return nullptr;
}

// -- Wayland (LayerShellQt) --

void AppGridController::configureWayland(QWindow *window)
{
    auto *layer = LayerShellQt::Window::get(window);
    // LayerTop: above normal windows but below OSD popups (like KRunner)
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    // The scope decides KWin's WindowType. The plasmoid keeps "appgrid"
    // (an overlay scope KWin's open/close effects exclude on plasmashell
    // surfaces anyway); the standalone overrides it (setLayerScope) with a
    // scope KWin maps to WindowType::Normal so Glide/Scale animate it.
    layer->setScope(m_layerScope);
    // Cover the full screen including panel exclusive zones
    layer->setExclusiveZone(-1);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft
                                                    | LayerShellQt::Window::AnchorRight));
}

QScreen *AppGridController::screenByName(const QString &name) const
{
    if (name.isEmpty()) {
        return nullptr;
    }
    const auto screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (screen->name() == name) {
            return screen;
        }
    }
    return nullptr;
}

QScreen *AppGridController::activeScreen() const
{
    // KWin is authoritative for the active output. QCursor::pos() is unreliable
    // on Wayland (no global pointer for a non-grabbing client), so match the
    // QScreen by the name KWin reports — exactly how KRunner finds its screen.
    auto msg =
        QDBusMessage::createMethodCall(AppGrid::KWinDbus::Service, AppGrid::KWinDbus::Path, AppGrid::KWinDbus::Interface, AppGrid::KWinDbus::ActiveOutputName);
    const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(msg);
    QScreen *screen = reply.isValid() ? screenByName(reply.value()) : nullptr;
    return screen ? screen : screenForCursor();
}

QScreen *AppGridController::panelScreen() const
{
    // The daemon has no containment, so ask the plasmoid's helper which screen
    // the panel icon is on (the "open on the panel's screen" option).
    auto msg = QDBusMessage::createMethodCall(AppGrid::PlasmoidDbus::Service,
                                              AppGrid::PlasmoidDbus::Path,
                                              AppGrid::PlasmoidDbus::Interface,
                                              AppGrid::PlasmoidDbus::PanelScreenName);
    const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(msg);
    return reply.isValid() ? screenByName(reply.value()) : nullptr;
}

// -- X11 (remove when targeting Plasma 6.8+ Wayland-only) --

#ifdef APPGRID_X11_SUPPORT
void AppGridController::configureX11(QWindow *window)
{
    window->setFlags(window->flags() | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    KX11Extras::setState(window->winId(), NET::SkipTaskbar | NET::SkipPager);
}
#endif

// -- Public API --

namespace
{
// The translucent overlay and the theme background need an alpha channel.
constexpr int kAlphaBufferBits = 8;
void enableAlphaChannel(QWindow *window)
{
    auto fmt = window->format();
    fmt.setAlphaBufferSize(kAlphaBufferBits);
    window->setFormat(fmt);
}

}

void AppGridController::configureWindow(QWindow *window)
{
    if (!window) {
        return;
    }

    enableAlphaChannel(window);

    if (KWindowSystem::isPlatformWayland()) {
        configureWayland(window);
    }
#ifdef APPGRID_X11_SUPPORT
    else {
        configureX11(window);
    }
#endif
}

void AppGridController::configurePanelWayland(QWindow *window)
{
    auto *layer = LayerShellQt::Window::get(window);
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    // m_layerScope decides KWin's WindowType. The plasmoid keeps its default
    // (a plasmashell surface KWin's Glide/Scale exclude regardless); the
    // standalone overrides it (setLayerScope) with a scope KWin maps to
    // WindowType::Normal so every window open/close effect animates it.
    layer->setScope(m_layerScope);
    layer->setExclusiveZone(0);
    // Anchor the top edge only: horizontally the surface stays centered (no
    // left/right anchor), vertically it sits at the top margin set by
    // positionPanelWindow() — that's how the user vertical offset applies to a
    // compositor-placed surface (like KRunner).
    layer->setAnchors(LayerShellQt::Window::AnchorTop);
}

void AppGridController::configurePanelWindow(QWindow *window)
{
    if (!window) {
        return;
    }
    enableAlphaChannel(window);
    if (KWindowSystem::isPlatformWayland()) {
        configurePanelWayland(window);
    }
#ifdef APPGRID_X11_SUPPORT
    else {
        configureX11(window);
    }
#endif
}

void AppGridController::positionPanelWindow(QWindow *window, int panelFullHeight, int verticalOffsetPercent, bool useActiveScreen)
{
    if (!window || !KWindowSystem::isPlatformWayland()) {
        return;
    }

    // useActiveScreen: the output under attention (KWin's active output). Else
    // the panel icon's screen (from the plasmoid helper); primary if no plasmoid.
    QScreen *target = useActiveScreen ? activeScreen() : panelScreen();
    if (!target) {
        target = QGuiApplication::primaryScreen();
    }
    if (!target) {
        return;
    }

    // Set the surface's screen EXPLICITLY (not wantsToBeOnActiveScreen): the
    // margin below is computed from this screen's height, so screen + margin must
    // agree. Letting the compositor pick the screen while QML computed the margin
    // off a lagging QScreen is what made the panel jump on a monitor switch.
    window->setScreen(target);
    auto *layer = LayerShellQt::Window::get(window);
    layer->setAnchors(LayerShellQt::Window::AnchorTop);
#ifdef HAVE_LAYERSHELLQT_SETSCREEN
    // Pin the surface to the chosen output explicitly. On older LayerShellQt
    // (no setScreen) the surface follows the QWindow::setScreen above instead.
    layer->setScreen(target);
#endif

    // Center the full panel; the user vertical offset is a fraction of the slack
    // between the full panel and the screen edge (PanelGeometry.verticalOffset in
    // QML keeps the same formula for the blur/input rect). A compact panel uses
    // the full height too, so it hangs from the full panel's top.
    const int screenHeight = target->geometry().height();
    const int centered = (screenHeight - panelFullHeight) / 2;
    const int slack = qMax(0, centered);
    const int offset = qRound(verticalOffsetPercent / 100.0 * slack);
    layer->setMargins(QMargins(0, qMax(0, centered + offset), 0, 0));
}

qreal AppGridController::windowDevicePixelRatio(QWindow *window) const
{
    return window ? window->devicePixelRatio() : 1.0;
}

void AppGridController::setInputRect(QWindow *window, int x, int y, int w, int h)
{
    if (!window) {
        return;
    }

    if (w <= 0 || h <= 0) {
        // Empty region = "remove mask" per Qt docs, restores full-window input.
        window->setMask(QRegion());
        return;
    }
    // On Wayland this maps to wl_surface.set_input_region(rect). Areas outside
    // the rect become pass-through, so events land on the surface below.
    window->setMask(QRegion(QRect(x, y, w, h)));
}

void AppGridController::notifyAppLaunched(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    // Standard convention used by Kicker, Kickoff and friends: the resource
    // URL is "applications:<storage-id>", tagged with our agent so other
    // tools can attribute the launch to AppGrid.
    KActivities::ResourceInstance::notifyAccessed(QUrl(PluginHelpers::ApplicationsUrlPrefix + storageId), QString(AppGrid::ApplicationId));
}

void AppGridController::addToTaskManager(const QString &desktopFile)
{
    if (desktopFile.isEmpty()) {
        return;
    }
    // Pinning to the Task Manager (with activities) is what Kicker does in-process
    // via the corona + libtaskmanager — unreachable from this separate process.
    // Delegate to the center plasmoid, which exports a helper on the session bus
    // and runs the real ContainmentInterface (see AppGridPlugin).
    auto msg = QDBusMessage::createMethodCall(AppGrid::PlasmoidDbus::Service,
                                              AppGrid::PlasmoidDbus::Path,
                                              AppGrid::PlasmoidDbus::Interface,
                                              AppGrid::PlasmoidDbus::AddToTaskManager);
    msg << desktopFile;
    QDBusConnection::sessionBus().asyncCall(msg);
}

void AppGridController::addToDesktop(const QString &desktopFile)
{
    if (desktopFile.isEmpty()) {
        return;
    }
    // The default Plasma desktop is Folder View, which shows the XDG Desktop
    // directory: drop a copy of the .desktop there (what Folder View does on an
    // app drag), marked executable so Plasma trusts it as a launcher. (Kicker
    // adds an org.kde.plasma.icon widget instead, but that resolves its .desktop
    // asynchronously and can't be driven reliably from out of process.)
    const QString desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (desktopDir.isEmpty()) {
        return;
    }
    QDir().mkpath(desktopDir);
    const QString dest = desktopDir + QLatin1Char('/') + QFileInfo(desktopFile).fileName();
    QFile::remove(dest);
    if (!QFile::copy(desktopFile, dest)) {
        return;
    }
    QFile::setPermissions(dest,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup | QFileDevice::ExeGroup
                              | QFileDevice::ReadOther | QFileDevice::ExeOther);
}

bool AppGridController::canPinToTaskManager() const
{
    auto bus = QDBusConnection::sessionBus();
    return bus.interface() && bus.interface()->isServiceRegistered(AppGrid::PlasmoidDbus::Service);
}

bool AppGridController::canAddToDesktop() const
{
    // A Folder View desktop is the only containment that shows the XDG Desktop
    // directory we drop into. Read the shell layout for one (live changes are
    // rare; the menu re-checks on each open).
    const KSharedConfig::Ptr cfg = KSharedConfig::openConfig(AppGrid::ShellLayout::AppletsConfig);
    const KConfigGroup containments = cfg->group(AppGrid::ShellLayout::ContainmentsGroup);
    const auto ids = containments.groupList();
    for (const QString &id : ids) {
        if (containments.group(id).readEntry(AppGrid::ShellLayout::PluginKey) == AppGrid::ShellLayout::FolderViewPlugin) {
            return true;
        }
    }
    return false;
}

void AppGridController::setSearchUsesFrecency(bool enabled)
{
    // Order matters: flip the filter model's usage flag first, then drive the
    // provider. On enable, the flag is already true when the provider's first
    // scoresChanged arrives → one invalidate. On disable, the flag is already
    // false when the provider's teardown clears its scores → no spurious
    // invalidate from the cleared hash.
    m_filterModel.setSearchUsesFrecency(enabled);
    m_frecencyProvider.setEnabled(enabled);
}

void AppGridController::setSearchShowsHidden(bool enabled)
{
    m_filterModel.setSearchShowsHidden(enabled);
}

// --- Prefix mode commands ---

// Validate that the given shell path is listed in /etc/shells.
// Falls back to /bin/sh if empty or not found.
static QString validatedShell(const QString &shell)
{
    if (shell.isEmpty()) {
        return QStringLiteral("/bin/sh");
    }

    QFile file(QStringLiteral("/etc/shells"));
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString contents = QString::fromUtf8(file.readAll());
        if (PluginHelpers::parseShells(contents).contains(shell)) {
            return shell;
        }
    }

    qWarning() << "AppGrid: shell not in /etc/shells, falling back to /bin/sh:" << shell;
    return QStringLiteral("/bin/sh");
}

void AppGridController::runInTerminal(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);

    // Wrap command so the terminal stays open after it finishes.
    const QString wrapped = QStringLiteral("%1 -c '%2; echo; echo \"[Press Enter to close]\"; read _'")
                                .arg(sh, QString(command).replace(QLatin1Char('\''), QStringLiteral("'\"'\"'")));

    auto *job = new KTerminalLauncherJob(wrapped);
    job->start();
}

void AppGridController::runCommand(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);
    QProcess::startDetached(sh, {QStringLiteral("-c"), command});
}

QStringList AppGridController::availableShells()
{
    QFile file(QStringLiteral("/etc/shells"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    const QString contents = QString::fromUtf8(file.readAll());

    QStringList shells;
    const auto candidates = PluginHelpers::parseShells(contents);
    for (const QString &shell : candidates) {
        if (QFile::exists(shell)) {
            shells.append(shell);
        }
    }
    return shells;
}

QVariantList AppGridController::appActions(const QString &storageId)
{
    QVariantList result;
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return result;
    }

    const auto actions = service->actions();
    for (const auto &action : actions) {
        if (action.text().isEmpty()) {
            continue;
        }
        QVariantMap map;
        map[QStringLiteral("text")] = action.text();
        map[QStringLiteral("icon")] = action.icon();
        map[QStringLiteral("name")] = action.name();
        result.append(map);
    }
    return result;
}

void AppGridController::launchAppAction(const QString &storageId, int actionIndex)
{
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    const auto actions = service->actions();
    if (actionIndex < 0 || actionIndex >= actions.size()) {
        return;
    }

    auto *job = new KIO::ApplicationLauncherJob(actions.at(actionIndex));
    job->start();
}

bool AppGridController::isDiscoverAvailable() const
{
    return static_cast<bool>(KService::serviceByDesktopName(QStringLiteral("org.kde.discover")));
}

bool AppGridController::canManageInDiscover(const QString &storageId) const
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return false;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return false;
    }

    // The .desktop we would launch from is the installed copy, so its location
    // authoritatively identifies the backend (PackageKit / Flatpak / Snap) —
    // more reliable than the AppStream id, which on its own can't tell apart
    // multiple sources of the same component.
    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    const QString backend = DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));
    if (backend.isEmpty() || !DiscoverBackends::isBackendInstalled(backend)) {
        return false;
    }

    // Only offer the menu when AppStream actually knows the component, so we
    // never open Discover on a dead appstream:// id.
    return !AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop")).isEmpty();
}

void AppGridController::openInDiscover(const QString &storageId)
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    // X-AppStream-Component wins if the .desktop declares one; otherwise ask the
    // AppStream pool for the canonical id.
    KDesktopFile desktopFile(service->entryPath());
    QString appId = desktopFile.desktopGroup().readEntry("X-AppStream-Component", QString());
    if (appId.isEmpty()) {
        appId = AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop"));
    }
    if (appId.isEmpty()) {
        return;
    }

    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    const QString backend = DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));

    // Target the backend that owns the installed copy so a multi-source app
    // (e.g. Flatpak + distro) opens the right version instead of Discover's
    // first match. CommandLauncherJob is KDE's launcher wrapper — carries the
    // desktop activation token + startup notification. Fall back to the bare
    // URL when the backend is unknown.
    if (!backend.isEmpty()) {
        // Discover's --backends identifies a backend by its plugin name, which
        // carries the -backend suffix (see `plasma-discover --listbackends`).
        const QString discoverBackend = backend + QStringLiteral("-backend");
        auto *job = new KIO::CommandLauncherJob(
            QStringLiteral("plasma-discover"),
            {QStringLiteral("--backends"), discoverBackend, QStringLiteral("--application"), QStringLiteral("appstream://") + appId});
        job->start();
    } else {
        auto *job = new KIO::OpenUrlJob(QUrl(QStringLiteral("appstream://") + appId));
        job->start();
    }
}

QVariantList AppGridController::listDirectory(const QString &path)
{
    return PluginHelpers::listDirectoryAt(path);
}

// --- System info ---

QVariantMap AppGridController::systemInfo(const QString &variant)
{
    QVariantMap info;
    // APPGRID_VERSION carries the dev-suffix on local builds; metadata.json's
    // version doesn't, so prefer the bake-in to reflect the running binary.
    info[QStringLiteral("appgridVersion")] = QString::fromUtf8(APPGRID_VERSION);
    info[QStringLiteral("plasmaVersion")] = QStringLiteral(PLASMA_VERSION_STRING);
    info[QStringLiteral("kfVersion")] = QStringLiteral(KCOREADDONS_VERSION_STRING);
    info[QStringLiteral("qtVersion")] = QString::fromLatin1(qVersion());
    info[QStringLiteral("sessionType")] = KWindowSystem::isPlatformWayland() ? QStringLiteral("Wayland") : QStringLiteral("X11");
    info[QStringLiteral("variant")] = variant;
    // isUniversalBuild() is a compile-time #ifdef constant, so it reads as a
    // known condition per build — expected, not a dead branch.
    // cppcheck-suppress knownConditionTrueFalse
    info[QStringLiteral("installType")] = isUniversalBuild() ? QStringLiteral("Universal package") : QStringLiteral("Distribution package");

    // OS info from /etc/os-release
    QFile osRelease(QStringLiteral("/etc/os-release"));
    if (osRelease.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QString pretty = PluginHelpers::parseOsPrettyName(QString::fromUtf8(osRelease.readAll()));
        if (!pretty.isEmpty()) {
            info[QStringLiteral("os")] = pretty;
        }
    }

    // Screen info
    const auto screens = QGuiApplication::screens();
    QStringList screenList;
    for (auto *screen : screens) {
        auto geo = screen->geometry();
        screenList.append(QStringLiteral("%1 (%2x%3 @ %4x)").arg(screen->name()).arg(geo.width()).arg(geo.height()).arg(screen->devicePixelRatio()));
    }
    info[QStringLiteral("screens")] = screenList.join(QStringLiteral(", "));

    return info;
}
