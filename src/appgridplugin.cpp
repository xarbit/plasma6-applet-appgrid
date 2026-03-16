/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include <KIO/OpenUrlJob>
#include <KRunner/ResultsModel>
#include <KTerminalLauncherJob>
#include <KWindowEffects>
#include <LayerShellQt/window.h>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <algorithm>
#include <QDir>
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

AppFilterModel *AppGridPlugin::appsModel()
{
    return &m_filterModel;
}

QAbstractItemModel *AppGridPlugin::runnerModel()
{
    return &m_runnerFilterModel;
}

KRunner::ResultsModel *AppGridPlugin::runnerSourceModel()
{
    return m_runnerModel;
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

void AppGridPlugin::configureWindow(QWindow *window)
{
    if (!window)
        return;

    auto fmt = window->format();
    fmt.setAlphaBufferSize(8);
    window->setFormat(fmt);

    if (auto *layerWindow = LayerShellQt::Window::get(window)) {
        layerWindow->setLayer(LayerShellQt::Window::LayerOverlay);
        layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layerWindow->setScope(QStringLiteral("appgrid"));
    }
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

void AppGridPlugin::runInTerminal(const QString &command, const QString &shell)
{
    if (command.trimmed().isEmpty())
        return;

    const QString sh = shell.isEmpty() ? QStringLiteral("/bin/sh") : shell;

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

    const QString sh = shell.isEmpty() ? QStringLiteral("/bin/sh") : shell;
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
