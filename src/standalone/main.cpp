/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Standalone `appgrid` executable. Hosts the shared GridPanel in a PlasmaWindow,
    in its OWN process — the same way KRunner builds its window. KWin derives a
    window's class from the client executable's filename; a plasmoid lives in
    plasmashell, which KWin's Glide/Scale open/close effects explicitly exclude.
    Running as a separate `appgrid` binary gives the window class "appgrid", so it
    is eligible for ALL window open/close effects, exactly like KRunner.
*/

#include "appgridconfig.h"
#include "appgridconstants.h"
#include "appgridcontroller.h"
#include "appgridstandalone.h"

#include <KAboutData>
#include <KConfigSkeleton>
#include <KLocalizedContext>
#include <KLocalizedString>
#include <PlasmaQuick/SharedQmlEngine>

#include <QApplication>
#include <QEvent>
#include <QEventLoop>
#include <QIcon>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QThread>
#include <QTimer>

namespace
{
/**
 * Keeps the daemon resident like KRunner. When the launcher's layer-shell window
 * hides as the last window, the Wayland platform posts a QEvent::Quit to
 * terminate the app — a path setQuitOnLastWindowClosed(false) does not cover, so
 * the daemon would die and the next launch would cold-start. This filter
 * swallows that stray Quit; only the explicit D-Bus Quit (an upgrade asking us
 * to step aside) sets @c allowQuit and lets the process exit.
 */
class ResidentQuitGuard : public QObject
{
public:
    bool allowQuit = false;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Quit && !allowQuit) {
            return true;
        }
        return QObject::eventFilter(watched, event);
    }
};

/**
 * The daemon's settings window. It runs in its OWN QQmlApplicationEngine using
 * the desktop colour platform (unlike the launcher's Plasma theme), created on
 * first show() and destroyed the moment it closes — never left hidden, because a
 * lingering qqc2-desktop-style window crashes when a later launcher hide
 * re-lays-out its stale style items. Recreated fresh on the next open
 * (ConfigWindow re-syncs from live on show), so nothing is lost.
 */
class SettingsWindow
{
public:
    SettingsWindow(AppGridConfig *config, AppGridConfig *buffer, AppGridController *controller)
        : m_config(config)
        , m_buffer(buffer)
        , m_controller(controller)
    {
    }

    ~SettingsWindow()
    {
        // Declared after the QApplication in main(), so destroyed before it while
        // the QQC2 style is still alive — a clean window teardown. Null first: the
        // delete hides the window, re-entering destroy() via visibleChanged.
        QQmlApplicationEngine *engine = m_engine;
        m_engine = nullptr;
        delete engine;
    }

    SettingsWindow(const SettingsWindow &) = delete;
    SettingsWindow &operator=(const SettingsWindow &) = delete;

    void show()
    {
        if (!m_engine) {
            load();
        }
        if (QQuickWindow *w = window()) {
            w->show();
            w->raise();
            w->requestActivate();
        }
    }

private:
    [[nodiscard]] QQuickWindow *window() const
    {
        if (!m_engine) {
            return nullptr;
        }
        const QList<QObject *> roots = m_engine->rootObjects();
        return roots.isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(roots.first());
    }

    void load()
    {
        m_engine = new QQmlApplicationEngine;
        m_engine->rootContext()->setContextObject(new KLocalizedContext(m_engine));
        // Fail-loud contract: ConfigWindow.qml declares these `required`, so a
        // missing injection errors at load instead of silently undefined (#6).
        m_engine->setInitialProperties({
            {QStringLiteral("appGridConfig"), QVariant::fromValue(m_config)},
            {QStringLiteral("appGridConfigBuffer"), QVariant::fromValue(m_buffer)},
            {QStringLiteral("appGridController"), QVariant::fromValue(m_controller)},
            {QStringLiteral("aboutData"), QVariant::fromValue(KAboutData::applicationData())},
        });
        m_engine->load(QUrl(QStringLiteral("qrc:/qt/qml/appgrid/ConfigWindow.qml")));
        if (QQuickWindow *w = window()) {
            QObject::connect(w, &QWindow::visibleChanged, m_engine, [this](bool visible) {
                if (!visible) {
                    destroy();
                }
            });
        }
    }

    void destroy()
    {
        if (!m_engine) {
            return;
        }
        m_engine->deleteLater();
        m_engine = nullptr;
    }

    AppGridConfig *const m_config;
    AppGridConfig *const m_buffer;
    AppGridController *const m_controller;
    QQmlApplicationEngine *m_engine = nullptr;
};
}

int main(int argc, char *argv[])
{
    // Match KRunner exactly: it forces no QtQuick style, no platform theme and
    // no palette. In a KDE session (XDG_CURRENT_DESKTOP=KDE) Qt auto-loads the
    // KDE platform theme and the org.kde.desktop Controls style, and the Plasma
    // theme + colours come from PlasmaWindow + SharedQmlEngine. Forcing any of
    // those here only fights that setup. QApplication (not QGui) so the KDE
    // platform style/palette apply.
    // Use the fractional device-pixel ratio as-is, the same as plasmashell and
    // KRunner. Without this the process falls back to Qt's default Round policy:
    // on a fractionally scaled display (e.g. 1.5) it rounds the scale up to 2.0,
    // so Kirigami.Units — icon sizes included — render ~1.3x larger than the
    // plasmoid's settings page, which runs inside plasmashell. Must be set before
    // the QApplication is constructed.
    QApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    QApplication app(argc, argv);

    // Set the translation domain BEFORE building KAboutData: its strings go
    // through i18n() and must resolve against AppGrid's catalog, not the default.
    KLocalizedString::setApplicationDomain(QByteArrayLiteral(APPGRID_APP_ID));

    // App metadata for the settings window's About page. The component name is
    // kept as "appgrid" (not the dev.xarbit.appgrid app id) so setApplicationData
    // leaves QApplication::applicationName as "appgrid" — KWin derives the
    // windowClass "appgrid appgrid" from it. setDesktopFileName ties the window
    // to the installed .desktop for icon / StartupWMClass matching.
    // Only the description is translatable copy; the product name, author,
    // copyright line, version and URLs are literal values, not strings to localize.
    KAboutData about(QStringLiteral("appgrid"),
                     QStringLiteral("AppGrid"),
                     QStringLiteral(APPGRID_VERSION),
                     i18n("A modern centered application grid launcher for KDE Plasma"),
                     KAboutLicense::GPL_V2,
                     QStringLiteral("© 2026 AppGrid Contributors"));
    about.addAuthor(QStringLiteral("Jason Scurtu"));
    about.setHomepage(QStringLiteral("https://appgrid.xarbit.dev"));
    about.setBugAddress(QByteArrayLiteral("https://github.com/xarbit/plasma6-applet-appgrid/issues"));
    about.setDesktopFileName(QStringLiteral("dev.xarbit.appgrid"));
    KAboutData::setApplicationData(about);
    // The About page sources its icon from the window icon (the KAboutData
    // component name "appgrid" has no installed icon — the app icon is named
    // after the app id). Set it so the page and the window get the real logo.
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("dev.xarbit.appgrid")));
    // Stay resident after the launcher window hides (it closes on focus loss),
    // so the process lives on as a daemon a second launch / shortcut can toggle —
    // like KRunner. setQuitOnLastWindowClosed handles the in-process last-window
    // path; the quit guard below covers the Wayland platform's QEvent::Quit, which
    // it does not.
    app.setQuitOnLastWindowClosed(false);
    ResidentQuitGuard quitGuard;
    app.installEventFilter(&quitGuard);

    const QStringList appArgs = app.arguments();
    // --configure: open the settings window straight away and skip auto-showing
    // the launcher (the plasmoid's "Configure Launcher…" when we were not yet
    // running). The launcher window is still created, ready for a later toggle.
    const bool openConfigOnStart = appArgs.contains(AppGrid::Standalone::FlagConfigure);
    // --compact: open collapsed to the search bar (the secondary "Open in Compact
    // Mode" shortcut fired while we were not yet running).
    const bool startCompact = appArgs.contains(AppGrid::Standalone::FlagCompact);
    // --replace: take over from a running (stale) daemon the plasmoid is quitting
    // after an upgrade — poll for the bus name to free instead of forwarding to it.
    const bool replaceRunning = appArgs.contains(AppGrid::Standalone::FlagReplace);
    // --plasmoid-id=<id>: the center plasmoid that opened the settings, so the
    // daemon edits that instance's panel button. Empty when launched directly
    // (terminal / autostart), which clears any button-edit binding.
    QString plasmoidId;
    for (const QString &arg : appArgs) {
        if (arg.startsWith(AppGrid::Standalone::FlagPlasmoidId)) {
            plasmoidId = arg.mid(AppGrid::Standalone::FlagPlasmoidId.size());
            break;
        }
    }

    // Single instance: a second launch toggles the running window and exits, so
    // the binary behaves like KRunner (one daemon, toggled on demand).
    AppGridStandalone standalone;
    if (!standalone.registerService()) {
        if (replaceRunning) {
            // The old daemon was just asked to Quit; wait for it to release the
            // name (it exits in its own process), then register as the new owner.
            constexpr int kReplaceRetries = 40;
            constexpr int kReplaceWaitMs = 25;
            bool registered = false;
            for (int i = 0; i < kReplaceRetries && !(registered = standalone.registerService()); ++i) {
                QThread::msleep(kReplaceWaitMs);
            }
            if (!registered) {
                AppGridStandalone::callToggleOnRunningInstance(plasmoidId);
                return 0;
            }
        } else {
            // A second launch forwards its intent to the running daemon: open
            // settings (carrying the origin plasmoid id, empty for a terminal
            // launch so the binding clears) for --configure, else toggle.
            if (openConfigOnStart) {
                AppGridStandalone::callConfigureOnRunningInstance(plasmoidId);
            } else {
                AppGridStandalone::callToggleOnRunningInstance(plasmoidId);
            }
            return 0;
        }
    }
    // The only sanctioned exit: an upgrade's D-Bus Quit. Lift the guard, then quit.
    QObject::connect(&standalone, &AppGridStandalone::quitRequested, &app, [&app, &quitGuard]() {
        quitGuard.allowQuit = true;
        app.quit();
    });

    // Alpha buffer is required for the transparent overlay + blur region. The
    // controller also sets this, but do it here too in case any QML window is
    // created before the controller's constructor runs.
    QQuickWindow::setDefaultAlphaBuffer(true);

    AppGridController controller;
    // A scope KWin does NOT special-case → scopeToType() falls through to
    // WindowType::Normal, so the window open/close effect animates it. (The
    // plasmoid keeps the "appgrid"/"utility"-style overlay scope.)
    controller.setLayerScope(QStringLiteral("appgrid-standalone"));

    // The plasmoid that opened this launcher session owns it: its Toggle/Configure
    // carry its id, so the settings window edits that instance's panel button.
    // Empty (terminal/autostart) → no owner, no button rows. Seed it from this
    // launch and update it whenever a (different) plasmoid toggles/configures us.
    controller.setButtonTargetId(plasmoidId);
    const auto setOwner = [&controller](const QString &id) {
        controller.setButtonTargetId(id);
    };
    QObject::connect(&standalone, &AppGridStandalone::toggleRequested, &controller, setOwner);
    QObject::connect(&standalone, &AppGridStandalone::toggleCompactRequested, &controller, setOwner);

    AppGridConfig config;

    // A second, never-saved AppGridConfig the settings window edits in isolation.
    // The launcher reads `config`, so editing a separate buffer keeps changes out
    // of the live launcher until the user hits Apply/OK (standard KCM behaviour):
    // ConfigWindow copies buffer -> config + save() on Apply, config -> buffer on
    // open/Reset, and compares the two for its dirty state.
    AppGridConfig configBuffer;

    // KConfigXT setters mutate in-memory items but don't persist. The launcher
    // writes settings live (hide an app, favourite toggles, recents, launch
    // counts), so flush them to the file with a debounced save plus a final one
    // at quit.
    //
    // The save trigger is every property's NOTIFY signal, NOT the skeleton's
    // configChanged(): the generated setters emit their per-property *Changed()
    // signal on set, but configChanged() only fires around save() itself — so a
    // configChanged()-driven timer would never start from a live write and the
    // change would be lost on a hard kill. Connecting each NOTIFY covers every
    // writable key and stays correct as the schema grows.
    // Debounce window for coalescing bursts of live config writes into one save.
    constexpr int kConfigSaveDebounceMs = 500;
    auto *saveTimer = new QTimer(&app);
    saveTimer->setSingleShot(true);
    saveTimer->setInterval(kConfigSaveDebounceMs);
    QObject::connect(saveTimer, &QTimer::timeout, &config, [&config]() {
        config.save();
    });
    const QMetaObject *configMeta = config.metaObject();
    const QMetaMethod startTimer = saveTimer->metaObject()->method(saveTimer->metaObject()->indexOfMethod("start()"));
    for (int i = configMeta->propertyOffset(); i < configMeta->propertyCount(); ++i) {
        const QMetaProperty prop = configMeta->property(i);
        if (prop.hasNotifySignal()) {
            QObject::connect(&config, prop.notifySignal(), saveTimer, startTimer);
        }
    }
    QObject::connect(&app, &QGuiApplication::aboutToQuit, &config, [&config]() {
        config.save();
    });

    // The app model defers its .desktop scan to the first event-loop pass (so it
    // never blocks plasmashell at startup). The plasmoid is created long before
    // its window opens, so the scan is always done by then; the standalone loads
    // its QML immediately, so pump the loop here to let the scan finish first —
    // otherwise the window's syncModelFromConfig() runs against an empty model
    // and the category bar / hidden-apps filter start blank until the next reset.
    constexpr int kModelScanBudgetMs = 500;
    QCoreApplication::processEvents(QEventLoop::AllEvents, kModelScanBudgetMs);

    // Load the QML through PlasmaQuick::SharedQmlEngine — the same engine
    // KRunner uses. Unlike a bare QQmlApplicationEngine it wires up everything a
    // plasmoid normally gets from the shell: the KLocalizedContext for i18n, the
    // Plasma theme + color scheme, and the Kirigami platform. Without it the
    // reused plasmoid QML renders unthemed and half-broken. rootContext() is a
    // child context, so our context properties don't leak into the shared engine.
    PlasmaQuick::SharedQmlEngine engine;
    engine.setTranslationDomain(QStringLiteral(APPGRID_APP_ID));
    engine.setInitializationDelayed(true);
    // Make Kirigami.Theme source its colours from Plasma::Theme (the active
    // Plasma Style), so text follows the Plasma desktop theme like the plasmoid
    // and KRunner — not the kdeglobals colour scheme (which may be a light scheme
    // and renders dark-on-dark over the dark Plasma background). Kirigami reads
    // this engine property to choose its colour platform plugin
    // (PlatformTheme::qmlAttachedProperties → findPlugin), and "Plasma" matches
    // the KirigamiPlasmaStyle plugin. This is what the Plasma QML stack sets up
    // for in-shell QML; a standalone binary must set it itself.
    engine.engine()->setProperty("_kirigamiTheme", QStringLiteral("Plasma"));
    // Inject the C++ dependencies as the entry root's *initial properties* (not
    // loose context properties): Main.qml declares each one `required`, so a
    // forgotten or renamed injection fails loudly at QML load instead of
    // silently resolving to undefined and half-breaking the launcher (#6).
    const QVariantHash entryProperties{
        {QStringLiteral("appGridController"), QVariant::fromValue(&controller)},
        {QStringLiteral("appGridConfig"), QVariant::fromValue(&config)},
        {QStringLiteral("appGridStandalone"), QVariant::fromValue(&standalone)},
        {QStringLiteral("appGridAutoShow"), !openConfigOnStart},
        {QStringLiteral("appGridStartCompact"), startCompact},
    };
    // Bundled at this qrc path by qt_add_resources (see CMakeLists). The root is
    // a PlasmaCore.Window (PlasmaWindow) hosting GridPanel as its mainItem.
    engine.setSource(QUrl(QStringLiteral("qrc:/qt/qml/appgrid/Main.qml")));
    engine.completeInitialization(entryProperties);
    if (!engine.rootObject()) {
        qWarning("AppGrid: failed to load standalone entry QML");
        return 1;
    }

    // Settings window, in its own engine (see SettingsWindow). Declared after the
    // QApplication so it is torn down before it — a clean QQC2 window teardown.
    SettingsWindow settings(&config, &configBuffer, &controller);

    // Configure (from a plasmoid's "Configure Launcher", or a terminal --configure)
    // retargets the button-edit owner to that plasmoid (empty clears it).
    QObject::connect(&standalone, &AppGridStandalone::configureRequested, &app, [&](const QString &plasmoidId) {
        controller.setButtonTargetId(plasmoidId);
        settings.show();
    });
    // The launcher's own Settings action: open the window keeping the owner set
    // by the Toggle that opened this launcher session.
    QObject::connect(&standalone, &AppGridStandalone::openSettingsRequested, &app, [&settings]() {
        settings.show();
    });

    // Launched as "appgrid --configure" (plasmoid, daemon not yet running): open
    // the settings window now. The launcher itself stayed hidden (appGridAutoShow).
    // plasmoidId targets that center plasmoid's button (empty for a terminal launch).
    if (openConfigOnStart) {
        standalone.Configure(plasmoidId);
    }

    return app.exec();
}
