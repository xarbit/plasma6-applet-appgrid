/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <KRunner/ResultsModel>

#include "appmodel.h"

class QWindow;
class SessionManagement;

/**
 * @brief Proxy that filters KRunner results already present in AppFilterModel.
 *
 * Hides runner results whose display name matches a visible app result,
 * preventing duplicate entries in the search view.
 */
class RunnerFilterModel : public QSortFilterProxyModel {
    Q_OBJECT
public:
    explicit RunnerFilterModel(QObject *parent = nullptr);
    void setAppModel(AppFilterModel *model);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    AppFilterModel *m_appModel = nullptr;
};

/**
 * @brief Main Plasma applet plugin for the AppGrid application launcher.
 *
 * Provides a macOS-style fullscreen application grid with category filtering,
 * search, blur effects, and session management actions. Exposes Q_INVOKABLE
 * methods for QML to configure the overlay window, manage blur, launch
 * session actions, and integrate with the desktop (task manager, desktop icons).
 */
class AppGridPlugin : public Plasma::Applet {
    Q_OBJECT
    Q_PROPERTY(AppFilterModel *appsModel READ appsModel CONSTANT)
    Q_PROPERTY(QAbstractItemModel *runnerModel READ runnerModel CONSTANT)
    Q_PROPERTY(KRunner::ResultsModel *runnerSourceModel READ runnerSourceModel CONSTANT)

public:
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);

    AppFilterModel *appsModel();
    QAbstractItemModel *runnerModel();
    KRunner::ResultsModel *runnerSourceModel();

    // --- Window management ---

    /** Configure @p window as a Wayland layer-shell overlay with alpha support. */
    Q_INVOKABLE void configureWindow(QWindow *window);

    /** Set a rounded-rect blur region on @p window matching the panel geometry. */
    Q_INVOKABLE void setBlurBehind(QWindow *window, bool enable, int x, int y, int w, int h, int radius);

    // --- Session actions ---

    Q_INVOKABLE void sleep();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void shutDown();
    Q_INVOKABLE void lock();
    Q_INVOKABLE void logOut();
    Q_INVOKABLE void switchUser();

    // --- Prefix mode commands ---

    /** Run @p command in the user's preferred terminal emulator using @p shell. */
    Q_INVOKABLE void runInTerminal(const QString &command, const QString &shell = QString());

    /** Run @p command via the configured shell without a terminal. */
    Q_INVOKABLE void runCommand(const QString &command, const QString &shell = QString());

    /** Returns list of installed shells from /etc/shells. */
    Q_INVOKABLE QStringList availableShells();

    /** Run a KRunner result by model index. Returns true if the UI should close. */
    Q_INVOKABLE bool runRunnerResult(int index);

    /** Launch KDE Menu Editor, optionally navigating to @p menuPath (e.g. "Education"). */
    Q_INVOKABLE void openMenuEditor(const QString &menuPath = QString());

    /** List directory contents at @p path. Returns a list of {name, path, isDir, icon}. */
    Q_INVOKABLE QVariantList listDirectory(const QString &path);

    /** Open @p filePath with the default application. */
    Q_INVOKABLE void openFile(const QString &filePath);

    // --- Desktop integration ---

    /** Open @p desktopFile in kmenuedit for editing. */
    Q_INVOKABLE void editApplication(const QString &desktopFile);

    /** Pin an application to the task manager by its @p storageId. */
    Q_INVOKABLE void pinToTaskManager(const QString &storageId);

    /** Add an application shortcut to the desktop by its @p desktopFile path. */
    Q_INVOKABLE void addToDesktop(const QString &desktopFile);

protected:
    bool m_useNativeActivation = false;

private:
    AppModel m_appModel;
    AppFilterModel m_filterModel;
    KRunner::ResultsModel *m_runnerModel = nullptr;
    RunnerFilterModel m_runnerFilterModel;
    SessionManagement *m_session = nullptr;
};
