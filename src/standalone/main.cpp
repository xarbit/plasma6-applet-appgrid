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

#include "appgrid_debug.h"
#include "appgridcontroller.h"
#include "appgridstandalone.h"
#include "configautosave.h"
#include "qmltypes.h"
#include "residentquitguard.h"
#include "settingswindow.h"
#include "standaloneoptions.h"
#include "windowconfigurator.h"

#include <KAboutData>
#include <KLocalizedQmlContext>
#include <KLocalizedString>
#include <PlasmaQuick/PlasmaQuick>

#include <QApplication>
#include <QEventLoop>
#include <QIcon>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QThread>

#include <memory>

int main(int argc, char *argv[])
{
    // Match KRunner exactly: it forces no QtQuick style, no platform theme and
    // no palette. In a KDE session (XDG_CURRENT_DESKTOP=KDE) Qt auto-loads the
    // KDE platform theme and the org.kde.desktop Controls style, and the Plasma
    // theme + colours come from PlasmaWindow + the engine setup below. Forcing any of
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

    const StandaloneOptions options = StandaloneOptions::parse(app.arguments());
    const QString &plasmoidId = options.plasmoidId;

    // Single instance: a second launch toggles the running window and exits, so
    // the binary behaves like KRunner (one daemon, toggled on demand).
    AppGridStandalone standalone;
    if (!standalone.registerService()) {
        if (options.replace) {
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
            // settings for --configure, toggle compact for --compact (the global
            // shortcut re-launches `appgrid --compact`), else a plain toggle. The
            // origin plasmoid id (empty for a terminal / shortcut launch) rides
            // along so the binding clears or retargets to match.
            if (options.configure) {
                AppGridStandalone::callConfigureOnRunningInstance(plasmoidId);
            } else if (options.compact) {
                AppGridStandalone::callToggleCompactOnRunningInstance(plasmoidId);
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
    // The shared QML names the C++ enums; register them before it loads.
    AppGridQml::registerTypes();
    // The launcher window's layer-shell setup and placement. A scope KWin does
    // NOT special-case → scopeToType() falls through to WindowType::Normal, so
    // the window open/close effect animates it.
    WindowConfigurator windowConfigurator(QStringLiteral("appgrid-standalone"));

    // The plasmoid that opened this launcher session owns it: its Toggle/Configure
    // carry its id, so the settings window edits that instance's panel button.
    // Empty (terminal/autostart) → no owner, no button rows. Seed it from this
    // launch and update it whenever a (different) plasmoid toggles/configures us.
    controller.plasmoidClient()->setButtonTargetId(plasmoidId);
    const auto setOwner = [&controller](const QString &id) {
        controller.plasmoidClient()->setButtonTargetId(id);
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

    // The launcher changes settings live; keep the file in step.
    ConfigAutosave::install(&config);

    // The app model defers its .desktop scan to the first event-loop pass (so it
    // never blocks plasmashell at startup). The plasmoid is created long before
    // its window opens, so the scan is always done by then; the standalone loads
    // its QML immediately, so pump the loop here to let the scan finish first —
    // otherwise the window's syncModelFromConfig() runs against an empty model
    // and the category bar / hidden-apps filter start blank until the next reset.
    constexpr int kModelScanBudgetMs = 500;
    QCoreApplication::processEvents(QEventLoop::AllEvents, kModelScanBudgetMs);

    // Load the QML in Plasma's shared QML engine, the one KRunner uses since
    // Plasma 6.8. Plasma::setupPlasmaStyle() has already pointed Kirigami.Theme
    // at the Plasma Style (text follows the Plasma desktop theme, not the
    // kdeglobals colour scheme) and set the Plasma tooltip style, so the reused
    // plasmoid QML renders like it does in the shell. Add the localized context
    // for i18n on top.
    const std::shared_ptr<QQmlEngine> engine = PlasmaQuick::globalEngine();
    KLocalization::setupLocalizedContext(engine.get());
    // Inject the C++ dependencies as the entry root's *initial properties* (not
    // loose context properties): Main.qml declares each one `required`, so a
    // forgotten or renamed injection fails loudly at QML load instead of
    // silently resolving to undefined and half-breaking the launcher (#6).
    const QVariantMap entryProperties{
        {QStringLiteral("appGridController"), QVariant::fromValue(&controller)},
        {QStringLiteral("appGridConfig"), QVariant::fromValue(&config)},
        {QStringLiteral("appGridStandalone"), QVariant::fromValue(&standalone)},
        {QStringLiteral("appGridWindow"), QVariant::fromValue(&windowConfigurator)},
        {QStringLiteral("appGridAutoShow"), !options.daemon && !options.configure},
        {QStringLiteral("appGridStartCompact"), options.compact},
    };
    // Bundled at this qrc path by qt_add_resources (see CMakeLists). The root is
    // a PlasmaCore.Window (PlasmaWindow) hosting GridPanel as its mainItem.
    QQmlComponent component(engine.get(), QUrl(QStringLiteral("qrc:/qt/qml/appgrid/Main.qml")));
    const std::unique_ptr<QObject> rootObject(component.createWithInitialProperties(entryProperties));
    if (!rootObject) {
        qCWarning(APPGRID) << "failed to load standalone entry QML:" << component.errorString();
        return 1;
    }

    // Settings window, in its own engine (see SettingsWindow). Declared after the
    // QApplication so it is torn down before it — a clean QQC2 window teardown.
    SettingsWindow settings(&config, &configBuffer, &controller);

    // Configure (from a plasmoid's "Configure Launcher", or a terminal --configure)
    // retargets the button-edit owner to that plasmoid (empty clears it).
    QObject::connect(&standalone, &AppGridStandalone::configureRequested, &app, [&](const QString &targetId) {
        controller.plasmoidClient()->setButtonTargetId(targetId);
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
    if (options.configure) {
        standalone.Configure(plasmoidId);
    }

    return app.exec();
}
