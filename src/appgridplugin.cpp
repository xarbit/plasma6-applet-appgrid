/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appgridplugin.h"

#include <KIO/OpenUrlJob>
#include <KTerminalLauncherJob>
#include <KWindowEffects>
#include <LayerShellQt/window.h>
#include <Plasma/Containment>
#include <Plasma/Corona>
#include <PlasmaQuick/AppletQuickItem>
#include <algorithm>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QUrl>
#include <QWindow>
#include <sessionmanagement.h>

K_PLUGIN_CLASS_WITH_JSON(AppGridPlugin, "metadata.json")

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
    QQuickWindow::setDefaultAlphaBuffer(true);
}

AppFilterModel *AppGridPlugin::appsModel()
{
    return &m_filterModel;
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

void AppGridPlugin::runInTerminal(const QString &command)
{
    if (command.trimmed().isEmpty())
        return;

    // Wrap command so the terminal stays open after it finishes.
    const QString wrapped = QStringLiteral("/bin/sh -c '%1; echo; echo \"[Press Enter to close]\"; read _'")
                                .arg(QString(command).replace(QLatin1Char('\''), QStringLiteral("'\"'\"'")));

    auto *job = new KTerminalLauncherJob(wrapped);
    job->start();
}

void AppGridPlugin::runCommand(const QString &command)
{
    if (command.trimmed().isEmpty())
        return;

    QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command});
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

#include "appgridplugin.moc"
