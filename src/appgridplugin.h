/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <KRunner/ResultsModel>
#include <QRect>

#include "appmodel.h"

class QScreen;
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
 * @brief Unified search model combining app results and KRunner results.
 *
 * Concatenates AppFilterModel rows (apps) with RunnerFilterModel rows (KRunner)
 * into a single list with unified role names. Enables one ListView for all search results.
 */
class UnifiedSearchModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int appResultCount READ appResultCount NOTIFY layoutChanged)
    Q_PROPERTY(int runnerResultCount READ runnerResultCount NOTIFY layoutChanged)

public:
    enum Roles {
        ResultTypeRole = Qt::UserRole + 100,
        NameRole,
        IconRole,
        SubtextRole,
        CategoryRole,
        StorageIdRole,
        DesktopFileRole,
        IsNewRole,
        ShortcutNumberRole,
        IsSectionBoundaryRole,
        SourceIndexRole,
    };
    Q_ENUM(Roles)

    explicit UnifiedSearchModel(QObject *parent = nullptr);

    void setAppModel(AppFilterModel *model);
    void setRunnerModel(RunnerFilterModel *model);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int appResultCount() const;
    int runnerResultCount() const;

    Q_INVOKABLE QVariantMap get(int row) const;

private slots:
    void onSourceChanged();
    void doReset();

private:
    AppFilterModel *m_appModel = nullptr;
    RunnerFilterModel *m_runnerModel = nullptr;
    int m_runnerSubtextRole = -1;
    int m_runnerCategoryRole = -1;
    int m_runnerUrlsRole = -1;
    bool m_resetPending = false;
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
    Q_PROPERTY(UnifiedSearchModel *searchModel READ searchModel CONSTANT)
    Q_PROPERTY(bool isWayland READ isWayland CONSTANT)

public:
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);

    AppFilterModel *appsModel();
    QAbstractItemModel *runnerModel();
    KRunner::ResultsModel *runnerSourceModel();
    UnifiedSearchModel *searchModel();
    bool isWayland() const;

    // --- Window management ---

    /** Configure @p window as an overlay (LayerShell on Wayland, flags on X11). */
    Q_INVOKABLE void configureWindow(QWindow *window);

    /** Update which screen the Wayland overlay appears on (no-op on X11). */
    Q_INVOKABLE void updateWindowScreen(QWindow *window, bool useActiveScreen);

    /** Returns the target screen geometry for the overlay (used by QML on X11). */
    Q_INVOKABLE QRect targetScreenGeometry(bool useActiveScreen);

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

    /** Returns application-defined actions (jumplist) for the given storageId. */
    Q_INVOKABLE QVariantList appActions(const QString &storageId);

    /** Launch a specific app action by storageId and action index. */
    Q_INVOKABLE void launchAppAction(const QString &storageId, int actionIndex);

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
    // --- Platform-specific window helpers ---

    QScreen *screenForCursor() const;
    QScreen *screenForPanel() const;

    void configureWayland(QWindow *window);
    void configureX11(QWindow *window);
    void updateScreenWayland(QWindow *window, QScreen *target, bool useActiveScreen);

    AppModel m_appModel;
    AppFilterModel m_filterModel;
    KRunner::ResultsModel *m_runnerModel = nullptr;
    RunnerFilterModel m_runnerFilterModel;
    UnifiedSearchModel m_searchModel;
    SessionManagement *m_session = nullptr;
};
