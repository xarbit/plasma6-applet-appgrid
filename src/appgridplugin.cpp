/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include "appgridconstants.h"
#include "appstreamresolver.h"
#include "discoverbackends.h"
#include "pluginhelpers.h"

#include <KConfigGroup>
#include <KDesktopFile>
#include <KGlobalAccel>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CommandLauncherJob>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>
#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>
#include <KRunner/ResultsModel>
#include <KService>
#include <KSvg/FrameSvg>
#include <KTerminalLauncherJob>
#include <KWindowEffects>
#include <KWindowSystem>
#include <QAction>
#include <QIcon>
#include <QKeySequence>

#include <PlasmaActivities/ResourceInstance>

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif
#ifdef APPGRID_X11_SUPPORT
#include <KX11Extras>
#endif
#include <LayerShellQt/window.h>
#include <Plasma/Containment>
#include <Plasma/Theme>
#include <PlasmaQuick/AppletQuickItem>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMimeDatabase>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QWindow>
#include <kcoreaddons_version.h>
#include <plasma_version.h>

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

    // PlasmoidItem::init() connects activated → setExpanded(true).
    // For custom Window mode, we add a second connection (fires after PlasmoidItem's)
    // that immediately reverses the expansion, preventing the native popup from showing.
    // The popup variant (AppGridPopupPlugin) sets m_useNativeActivation = true to skip this.
    QTimer::singleShot(0, this, [this]() {
        if (!m_useNativeActivation) {
            auto *quickItem = PlasmaQuick::AppletQuickItem::itemForApplet(this);
            if (quickItem) {
                // Context object is quickItem (not this): the lambda captures it
                // raw, so the connection must die with it — the applet outlives
                // the QML representation when Plasma recreates it.
                connect(this, &Plasma::Applet::activated, quickItem, [quickItem]() {
                    quickItem->setProperty("expanded", false);
                });
            }
            // Compact mode is a center-variant feature (the popup variant
            // is already small + anchored). Registering the shortcut only
            // here also avoids a two-action contention on the same
            // KGlobalAccel componentName when both variants are installed
            // or briefly coexist during a variant switch.
            registerCompactShortcut();
        }
    });
}

AppGridPlugin::~AppGridPlugin() = default;

void AppGridPlugin::registerCompactShortcut()
{
    if (m_compactAction) {
        return;
    }

    // componentName + componentDisplayName are KGlobalAccel dynamic properties
    // (not object identity). Matching the values Plasma uses for its own
    // applet-activation shortcut (the applet's pluginId + display name) merges
    // our action into the same group in System Settings → Keyboard, so the
    // user sees both the primary "open" (owned by Plasma) and "open compact"
    // (owned by us) shortcuts side-by-side under one AppGrid heading, with
    // the applet's own icon.
    const auto meta = pluginMetaData();
    m_compactAction = new QAction(QIcon::fromTheme(meta.iconName()), i18n("Open in Compact Mode"), this);
    m_compactAction->setObjectName(QStringLiteral("appgrid_open_compact"));
    m_compactAction->setProperty("componentName", meta.pluginId());
    m_compactAction->setProperty("componentDisplayName", meta.name());

    // Empty default by design. Any prefab combo (Meta+Space, Alt+Space,
    // Ctrl+Space, …) collides with input-method engines like IBus / Fcitx5
    // for some users. The action is registered with an empty default so the
    // KCM entry stays visible under System Settings → Keyboard → Shortcuts;
    // user opts in by binding a key they know is free on their setup. The
    // two-call sequence mirrors the canonical Plasma pattern:
    //   1. setDefaultShortcut(NoAutoloading) force-publishes the canonical
    //      default (here, empty) so "Restore Defaults" cleanly clears any
    //      prior binding rather than restoring stale state from the daemon.
    //   2. setShortcut(Autoloading) honors the user's saved binding if any,
    //      else falls back to the default we just registered.
    const QList<QKeySequence> defaults;
    KGlobalAccel::self()->setDefaultShortcut(m_compactAction, defaults, KGlobalAccel::NoAutoloading);
    KGlobalAccel::self()->setShortcut(m_compactAction, defaults, KGlobalAccel::Autoloading);

    connect(m_compactAction, &QAction::triggered, this, &AppGridPlugin::compactActivated);
}

AppFilterModel *AppGridPlugin::appsModel() const
{
    return const_cast<AppFilterModel *>(&m_filterModel);
}

QAbstractItemModel *AppGridPlugin::runnerModel() const
{
    return const_cast<RunnerFilterModel *>(&m_runnerFilterModel);
}

QObject *AppGridPlugin::runnerSourceModel() const
{
    return m_runnerModel;
}

void AppGridPlugin::applyRunnerFavorites()
{
    if (m_runnerModel) {
        m_runnerModel->setFavoriteIds(PluginHelpers::readRunnerFavorites(m_krunnerConfig));
    }
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

QModelIndex AppGridPlugin::runnerSourceIndex(int proxyIndex) const
{
    if (!m_runnerModel || proxyIndex < 0 || proxyIndex >= m_runnerFilterModel.rowCount()) {
        return {};
    }
    return m_runnerFilterModel.mapToSource(m_runnerFilterModel.index(proxyIndex, 0));
}

bool AppGridPlugin::runRunnerResult(int index)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->run(sourceIdx);
}

bool AppGridPlugin::runRunnerAction(int index, int actionIndex)
{
    const auto sourceIdx = runnerSourceIndex(index);
    return sourceIdx.isValid() && m_runnerModel->runAction(sourceIdx, actionIndex);
}

QString AppGridPlugin::runnerSubstitutionText(int index)
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

QScreen *AppGridPlugin::screenForCursor() const
{
    const QPoint pos = QCursor::pos();
    for (auto *screen : QGuiApplication::screens()) {
        if (screen->geometry().contains(pos)) {
            return screen;
        }
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
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft
                                                    | LayerShellQt::Window::AnchorRight));
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
        if (target) {
            window->setScreen(target);
        }
        QT_WARNING_PUSH
        QT_WARNING_DISABLE_DEPRECATED
        layer->setScreenConfiguration(useActiveScreen ? LayerShellQt::Window::ScreenFromCompositor : LayerShellQt::Window::ScreenFromQWindow);
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
    if (!window) {
        return;
    }

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
    if (!window || !KWindowSystem::isPlatformWayland()) {
        return;
    }

    QScreen *target = useActiveScreen ? screenForCursor() : screenForPanel();
    updateScreenWayland(window, target, useActiveScreen);
}

QRect AppGridPlugin::targetScreenGeometry(bool useActiveScreen)
{
    QScreen *target = useActiveScreen ? screenForCursor() : screenForPanel();
    if (!target) {
        target = QGuiApplication::primaryScreen();
    }
    return target ? target->geometry() : QRect();
}

namespace
{
// Rounded-rect region (square corners removed, elliptical arcs added) matching
// the ShadowedRectangle's radius — used in solid-colour mode, where that
// rectangle is the visible surface.
QRegion roundedRectRegion(const QRect &r, int radius)
{
    const int d = radius * 2;
    QRegion region(r);

    QRegion corners;
    corners += QRegion(r.x(), r.y(), radius, radius);
    corners += QRegion(r.right() + 1 - radius, r.y(), radius, radius);
    corners += QRegion(r.x(), r.bottom() + 1 - radius, radius, radius);
    corners += QRegion(r.right() + 1 - radius, r.bottom() + 1 - radius, radius, radius);
    region -= corners;

    region += QRegion(r.x(), r.y(), d, d, QRegion::Ellipse);
    region += QRegion(r.right() + 1 - d, r.y(), d, d, QRegion::Ellipse);
    region += QRegion(r.x(), r.bottom() + 1 - d, d, d, QRegion::Ellipse);
    region += QRegion(r.right() + 1 - d, r.bottom() + 1 - d, d, d, QRegion::Ellipse);

    return region;
}
}

// Mask of the theme's popup-background SVG at @p r — the same shape the panel's
// FrameSvgItem paints under theme chrome. KWin blurs a hard-edged region, so
// matching it to the drawn background lets the background's own antialiased
// corner cover the blur edge (how Plasma's Dialog hides its rectangular blur).
// Empty if the theme ships no mask, so callers fall back to the rounded rect.
//
// @p devicePixelRatio must be the panel window's ratio. FrameSvg renders the
// mask at that ratio and scales it back to logical pixels, so its edges land on
// the same fractional logical coordinates as the painted FrameSvgItem (which
// takes its ratio from the window). KWindowEffects wants a logical region and
// KWin rescales it to device pixels itself; if this frame were left at the
// default ratio of 1, the mask edge and the painted edge would round to
// different device pixels under fractional scaling — a 1px blur seam that grows
// toward the bottom-right corner (#188). This mirrors KSvg's FrameSvgItem,
// which sets the same ratio on its own FrameSvg.
QRegion AppGridPlugin::themeBackgroundMask(const QRect &r, qreal devicePixelRatio) const
{
    KSvg::FrameSvg *frame = themeBackgroundFrame(QStringLiteral("dialogs/background"));
    frame->setDevicePixelRatio(devicePixelRatio);
    frame->resizeFrame(r.size());
    return frame->mask().translated(r.topLeft());
}

void AppGridPlugin::setBackgroundEffects(QWindow *window, bool enableBlur, bool enableContrast, int x, int y, int w, int h, int radius, bool useThemeMask)
{
    if (!window) {
        return;
    }

    // A degenerate rect would leave the region empty, and KWindowEffects treats
    // an empty region with enable=true as "the whole window" — on our
    // full-screen layer surface that frosts the entire screen (the window-leak
    // seen when the panel rect is still 0-sized during a surface reconfig). So
    // only enable the effects when we actually have a panel rect to clip to.
    const bool validRect = w > 0 && h > 0;

    QRegion region;
    if ((enableBlur || enableContrast) && validRect) {
        const QRect rect(x, y, w, h);
        // Theme chrome: match the blur to the drawn FrameSvg shape so its
        // antialiased corner covers the blur edge. Fall back to the rounded rect
        // for solid-colour mode and themes that ship no mask.
        if (useThemeMask) {
            region = themeBackgroundMask(rect, window->devicePixelRatio());
        }
        if (region.isEmpty()) {
            region = roundedRectRegion(rect, radius);
        }
    }

    KWindowEffects::enableBlurBehind(window, enableBlur && validRect, region);

    // Background-contrast triple from the active Plasma theme. Each theme
    // tunes its own contrast/intensity/saturation values to keep panel text
    // legible against busy wallpapers after blur softens the edges; honoring
    // the theme means Breeze, Klassy, custom themes etc. each get the look
    // they were designed for instead of a hardcoded value. Themes that opt
    // out via backgroundContrastEnabled() get a clean disable even when the
    // caller requested it.
    Plasma::Theme theme;
    const bool contrastEnabled = enableContrast && validRect && theme.backgroundContrastEnabled();
    KWindowEffects::enableBackgroundContrast(window,
                                             contrastEnabled,
                                             theme.backgroundContrast(),
                                             theme.backgroundIntensity(),
                                             theme.backgroundSaturation(),
                                             region);
}

KSvg::FrameSvg *AppGridPlugin::themeBackgroundFrame(const QString &imagePath) const
{
    if (!m_themeBackgroundFrame) {
        m_themeBackgroundFrame = std::make_unique<KSvg::FrameSvg>();
        m_themeBackgroundFrame->setEnabledBorders(KSvg::FrameSvg::AllBorders);
    }
    if (m_themeBackgroundFrame->imagePath() != imagePath) {
        m_themeBackgroundFrame->setImagePath(imagePath);
    }
    return m_themeBackgroundFrame.get();
}

int AppGridPlugin::themeBackgroundCornerRadius(const QString &imagePath) const
{
    KSvg::FrameSvg *frame = themeBackgroundFrame(imagePath);
    // The mask prefix carries the theme's rounded shape; some themes draw a
    // square frame and round purely via that mask. Prefer the mask corner, fall
    // back to the frame corner.
    for (const QString &corner : {QStringLiteral("mask-topleft"), QStringLiteral("topleft")}) {
        if (frame->hasElement(corner)) {
            return qRound(frame->elementSize(corner).width());
        }
    }
    return 0;
}

qreal AppGridPlugin::windowDevicePixelRatio(QWindow *window) const
{
    return window ? window->devicePixelRatio() : 1.0;
}

void AppGridPlugin::setInputRect(QWindow *window, int x, int y, int w, int h)
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

void AppGridPlugin::notifyAppLaunched(const QString &storageId)
{
    if (storageId.isEmpty()) {
        return;
    }
    // Standard convention used by Kicker, Kickoff and friends: the resource
    // URL is "applications:<storage-id>", tagged with our agent so other
    // tools can attribute the launch to AppGrid.
    KActivities::ResourceInstance::notifyAccessed(QUrl(PluginHelpers::ApplicationsUrlPrefix + storageId), QString(AppGrid::ApplicationId));
}

void AppGridPlugin::setSearchUsesFrecency(bool enabled)
{
    // Order matters: flip the filter model's usage flag first, then drive the
    // provider. On enable, the flag is already true when the provider's first
    // scoresChanged arrives → one invalidate. On disable, the flag is already
    // false when the provider's teardown clears its scores → no spurious
    // invalidate from the cleared hash.
    m_filterModel.setSearchUsesFrecency(enabled);
    m_frecencyProvider.setEnabled(enabled);
}

void AppGridPlugin::setSearchShowsHidden(bool enabled)
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

void AppGridPlugin::runInTerminal(const QString &command, const QString &shell)
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

void AppGridPlugin::runCommand(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty()) {
        return;
    }

    const QString sh = validatedShell(shell);
    QProcess::startDetached(sh, {QStringLiteral("-c"), command});
}

QStringList AppGridPlugin::availableShells()
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

QVariantList AppGridPlugin::appActions(const QString &storageId)
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

void AppGridPlugin::launchAppAction(const QString &storageId, int actionIndex)
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

bool AppGridPlugin::isDiscoverAvailable() const
{
    return static_cast<bool>(KService::serviceByDesktopName(QStringLiteral("org.kde.discover")));
}

bool AppGridPlugin::canManageInDiscover(const QString &storageId) const
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return false;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return false;
    }

    // The .desktop we would launch from is the installed copy, so its
    // location authoritatively identifies the backend (PackageKit / Flatpak
    // / Snap) — more reliable than the AppStream id, which on its own can't
    // tell apart multiple sources of the same component.
    const auto resolvedPath = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, service->entryPath());
    const QString backend = DiscoverBackends::forInstallSource(AppModel::detectInstallSource(service->exec(), resolvedPath));
    if (backend.isEmpty() || !DiscoverBackends::isBackendInstalled(backend)) {
        return false;
    }

    // Only offer the menu when AppStream actually knows the component, so we
    // never open Discover on a dead appstream:// id.
    return !AppStreamResolver::resolve(service->desktopEntryName() + QLatin1String(".desktop")).isEmpty();
}

void AppGridPlugin::openInDiscover(const QString &storageId)
{
    if (storageId.isEmpty() || !isDiscoverAvailable()) {
        return;
    }
    auto service = KService::serviceByStorageId(storageId);
    if (!service) {
        return;
    }

    // X-AppStream-Component wins if the .desktop declares one; otherwise ask
    // the AppStream pool for the canonical id.
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
        // Discover's --backends identifies a backend by its plugin name,
        // which carries the -backend suffix (see `plasma-discover --listbackends`).
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

QVariantList AppGridPlugin::listDirectory(const QString &path)
{
    return PluginHelpers::listDirectoryAt(path);
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
    info[QStringLiteral("sessionType")] = KWindowSystem::isPlatformWayland() ? QStringLiteral("Wayland") : QStringLiteral("X11");
    info[QStringLiteral("variant")] = m_useNativeActivation ? QStringLiteral("Panel") : QStringLiteral("Center");
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
