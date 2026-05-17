/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <Plasma/Applet>
#include <KRunner/ResultsModel>
#include <QRect>

#include "appmodel.h"
#include "appfiltermodel.h"

#ifdef APPGRID_UNIVERSAL_BUILD
#include "updatechecker.h"
#endif

class QScreen;
class QWindow;

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
        InstallSourceRole,
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
 * Provides a centered application grid overlay with category filtering,
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
    // True when compiled with APPGRID_UNIVERSAL_BUILD. QML uses this to
    // hide the "Check for updates" setting on distro-package builds.
    // systemInfo() surfaces this as the "Install" row in the i: view.
    Q_PROPERTY(bool isUniversalBuild READ isUniversalBuild CONSTANT)
#ifdef APPGRID_UNIVERSAL_BUILD
    // Only exposed on universal builds — non-universal builds don't carry
    // QtNetwork or this class at all.
    Q_PROPERTY(UpdateChecker *updateChecker READ updateChecker CONSTANT)
#endif

public:
    AppGridPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);

    AppFilterModel *appsModel() const;
    QAbstractItemModel *runnerModel() const;
    KRunner::ResultsModel *runnerSourceModel() const;
    UnifiedSearchModel *searchModel() const;
    bool isUniversalBuild() const;
#ifdef APPGRID_UNIVERSAL_BUILD
    UpdateChecker *updateChecker() const;
#endif
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

    /**
     * Restrict pointer input on @p window to the rectangle (x,y,w,h). The
     * rest of the window becomes pass-through — events fall through to the
     * surface below (e.g. the panel/taskbar/desktop under our full-screen
     * layer overlay). If @p w or @p h is zero, the mask is cleared and the
     * entire window receives input again.
     *
     * Used while a drag-out is in flight: the centred grid panel keeps full
     * input (so internal favorites reorder still works) while the surrounding
     * dim overlay becomes pass-through so the user can drop on external
     * targets that are otherwise covered by AppGrid.
     */
    Q_INVOKABLE void setInputRect(QWindow *window, int x, int y, int w, int h);

    /**
     * Broadcast an app launch to the system-wide KActivities database so
     * other Plasma launchers (Kickoff, KRunner, etc.) count AppGrid as a
     * contributing launcher. AppGrid does NOT read this data back; it's a
     * one-way courtesy notification. See #95 for the rationale.
     */
    Q_INVOKABLE void notifyAppLaunched(const QString &storageId);

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

    /** List directory contents at @p path. Returns a list of {name, path, isDir, icon}. */
    Q_INVOKABLE QVariantList listDirectory(const QString &path);

    // --- System info ---

    /** Returns system/environment info for issue reporting. */
    Q_INVOKABLE QVariantMap systemInfo();

protected:
    bool m_useNativeActivation = false;

private:
    // --- Platform-specific window helpers ---

    QScreen *screenForCursor() const;
    QScreen *screenForPanel() const;

    void configureWayland(QWindow *window);
#ifdef APPGRID_X11_SUPPORT
    void configureX11(QWindow *window);
#endif
    void updateScreenWayland(QWindow *window, QScreen *target, bool useActiveScreen);

    AppModel m_appModel;
    AppFilterModel m_filterModel;
    KRunner::ResultsModel *m_runnerModel = nullptr;
    RunnerFilterModel m_runnerFilterModel;
    UnifiedSearchModel m_searchModel;
#ifdef APPGRID_UNIVERSAL_BUILD
    mutable UpdateChecker *m_updateChecker = nullptr;
#endif
};
