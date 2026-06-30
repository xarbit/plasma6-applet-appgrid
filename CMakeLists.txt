# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ECM ships KDEInstallDirs, which defines the KDE_INSTALL_* paths this build
# installs into. Include it before find_package(Qt6) — Qt pulls in
# GNUInstallDirs, and if that runs first the KDE_INSTALL_* dirs get shadowed
# by CMAKE_INSTALL_*, which ECM warns about.
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

# Test suite off by default so distro/makepkg builds stay lean; the ci/tests
# presets turn it on. Declared before KDECMakeSettings, which pulls in CTest and
# would otherwise default it ON.
option(BUILD_TESTING "Build the test suite" OFF)

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)

# X11 support — disable when targeting Plasma 6.8+ (Wayland-only)
option(ENABLE_X11 "Enable X11 session support" ON)

# Universal-build flag — enables the in-app update checker (notify-only,
# opt-in via config). Distros that ship via their package manager should
# leave this OFF so the package manager remains the source of truth for
# updates. The universal tarball CI job turns it ON.
option(APPGRID_UNIVERSAL_BUILD "Compile in the in-app update checker for universal tarball releases" OFF)

# Install D-Bus + systemd user units so the daemon is started on demand by an
# activating method call (like KRunner's plasma-krunner.service), instead of an
# explicit launch. The plasmoid keeps the explicit-launch path as the fallback
# when this is off.
option(APPGRID_DBUS_ACTIVATION "Install D-Bus/systemd activation units for the daemon" ON)
# The relocatable universal tarball has no fixed install prefix, so the absolute
# Exec paths baked into the activation units would be wrong — keep it explicit.
if(APPGRID_UNIVERSAL_BUILD)
    set(APPGRID_DBUS_ACTIVATION OFF)
endif()

# Compiler warnings. Off by default so distro/makepkg builds stay quiet and a
# new compiler warning can never break a user's build. CI turns this ON to add
# -Wall/-Wextra -Werror, so warnings fail the pipeline instead.
option(APPGRID_STRICT_WARNINGS "Enable -Wall/-Wextra and treat warnings as errors (CI gate)" OFF)

# Resolved version baked into the binary (update checker + i: view):
#   1. APPGRID_VERSION_OVERRIDE wins (CI injects exact tag here).
#   2. On a release tag → CMAKE_PROJECT_VERSION (clean "2.0.0").
#   3. Local dev → "${BASE}-dev.<N>+self.g<sha>". The +self.g… build-metadata
#      tail flags hand-built binaries vs CI artifacts; semver ignores build
#      metadata for ordering so update behavior matches.
set(APPGRID_VERSION_OVERRIDE "" CACHE STRING
    "Explicit version string to bake into the binary (overrides git-derived)")
if(APPGRID_VERSION_OVERRIDE)
    set(APPGRID_VERSION_STRING "${APPGRID_VERSION_OVERRIDE}")
else()
    set(APPGRID_VERSION_STRING "${CMAKE_PROJECT_VERSION}")
    find_package(Git QUIET)
    if(Git_FOUND AND EXISTS "${CMAKE_SOURCE_DIR}/.git")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} describe --tags --exact-match HEAD
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            OUTPUT_QUIET ERROR_QUIET
            RESULT_VARIABLE _appgrid_on_tag
        )
        if(NOT _appgrid_on_tag EQUAL 0)
            execute_process(
                COMMAND ${GIT_EXECUTABLE} describe --tags --abbrev=0
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                OUTPUT_VARIABLE _appgrid_last_tag
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            if(_appgrid_last_tag)
                execute_process(
                    COMMAND ${GIT_EXECUTABLE} rev-list ${_appgrid_last_tag}..HEAD --count
                    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                    OUTPUT_VARIABLE _appgrid_rev_count
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
            else()
                execute_process(
                    COMMAND ${GIT_EXECUTABLE} rev-list --count HEAD
                    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                    OUTPUT_VARIABLE _appgrid_rev_count
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET
                )
            endif()
            execute_process(
                COMMAND ${GIT_EXECUTABLE} rev-parse --short=7 HEAD
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                OUTPUT_VARIABLE _appgrid_git_sha
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            if(_appgrid_rev_count AND _appgrid_git_sha)
                set(APPGRID_VERSION_STRING
                    "${CMAKE_PROJECT_VERSION}-dev.${_appgrid_rev_count}+self.g${_appgrid_git_sha}")
            endif()
        endif()
    endif()
endif()
message(STATUS "AppGrid version string: ${APPGRID_VERSION_STRING}")

# Single source for the application id. Feeds both the KDE translation domain
# (so C++ can use plain i18n()) and the AppGrid::ApplicationId constant
# (KActivities agent id) — see src/appgridconstants.h.
set(APPGRID_APP_ID "dev.xarbit.appgrid")

find_package(Qt6 REQUIRED COMPONENTS Quick Gui DBus)
# Widgets + QuickControls2 are needed only by the standalone executable (KDE
# platform palette + the org.kde.desktop Controls style); the plasmoid gets
# both from the Plasma shell.
find_package(Qt6 REQUIRED COMPONENTS Widgets QuickControls2)
# KColorSchemeManager (standalone only): track the system color scheme so the
# app follows the user's dark/light choice live, like every other KDE app.
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS ColorScheme)
if(APPGRID_UNIVERSAL_BUILD)
    find_package(Qt6 REQUIRED COMPONENTS Network)
endif()
# KF6 floor matches the oldest Plasma 6 desktop we still ship for
# (Plasma 6.0 → KF6 6.0). Newer APIs must be gated behind explicit
# version checks rather than raising this minimum.
set(KF6_MIN_VERSION 6.0)
set(PLASMA_MIN_VERSION 6.0)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Config
    CoreAddons
    I18n
    IconThemes
    KIO
    Runner
    Service
    Svg
    WindowSystem
)
find_package(LayerShellQt REQUIRED)
# LayerShellQt::Window::setScreen() pins the layer surface to a specific output
# (multi-monitor positioning). It is newer API — missing on e.g. Ubuntu 25.10's
# LayerShellQt — so detect it and fall back to QWindow::setScreen() where absent.
include(CheckCXXSourceCompiles)
include(CMakePushCheckState)
cmake_push_check_state()
set(CMAKE_REQUIRED_LIBRARIES LayerShellQt::Interface)
check_cxx_source_compiles("
#include <LayerShellQt/Window>
int main() { LayerShellQt::Window::get(nullptr)->setScreen(nullptr); return 0; }
" HAVE_LAYERSHELLQT_SETSCREEN)
cmake_pop_check_state()
if(HAVE_LAYERSHELLQT_SETSCREEN)
    add_compile_definitions(HAVE_LAYERSHELLQT_SETSCREEN)
endif()
find_package(Plasma ${PLASMA_MIN_VERSION} REQUIRED)
find_package(PlasmaQuick ${PLASMA_MIN_VERSION} REQUIRED)
# Write-side: KActivities::ResourceInstance::notifyAccessed broadcasts AppGrid
# launches to the system-wide KActivities database so Kickoff / KRunner / Plasma
# Activities see AppGrid as a contributing launcher.
# Read-side: PlasmaActivitiesStats exposes the frecency-ordered ResultModel that
# powers the opt-in "Bias results by recent usage" search ranking (see
# FrecencyProvider). The grid sort intentionally stays off this — #95 close-out.
find_package(PlasmaActivities REQUIRED)
find_package(PlasmaActivitiesStats REQUIRED)
# AppStream metadata pool — resolves an app's .desktop id to its canonical
# component id across all backends (distro/PackageKit, Flatpak, Snap) for
# the "Manage in Discover" action. Same resolver Kicker and Discover use.
find_package(AppStreamQt REQUIRED)

set(APPGRID_COMMON_LIBS
    Qt6::Quick
    Qt6::Gui
    Qt6::DBus
    Plasma::Plasma
    KF6::ConfigCore
    KF6::Service
    KF6::I18n
    KF6::CoreAddons
    KF6::KIOGui
    KF6::WindowSystem
    KF6::IconThemes
    KF6::Svg
    LayerShellQt::Interface
    Plasma::PlasmaQuick
    KF6::Runner
    Plasma::Activities
    Plasma::ActivitiesStats
    AppStreamQt
)


# --- Shared C++ sources (both variants) ---
# Everything except the per-variant plugin register (appgridplugin_register.cpp
# for center, appgridpanelplugin.* for panel), which the calls add inline.
set(APPGRID_COMMON_SOURCES
    src/appactionid.cpp
    src/appactionid.h
    src/appgridcontroller.cpp
    src/appgridcontroller.h
    src/appgridfavoritesmodel.cpp
    src/appgridfavoritesmodel.h
    src/favoriteid.cpp
    src/favoriteid.h
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appstreamresolver.cpp
    src/appstreamresolver.h
    src/appmodel.cpp
    src/appmodel.h
    src/appmodelassembly.cpp
    src/appmodelassembly.h
    src/appfiltermodel.cpp
    src/defaultappsresolver.cpp
    src/defaultappsresolver.h
    src/appfiltermodel.h
    src/categorymapping.cpp
    src/categorymapping.h
    src/categoryqueries.cpp
    src/categoryqueries.h
    src/discoverbackends.cpp
    src/discoverbackends.h
    src/pluginhelpers.cpp
    src/pluginhelpers.h
    src/searchranking.cpp
    src/searchranking.h
    src/launchbookkeeping.cpp
    src/launchbookkeeping.h
    src/launchstatestore.cpp
    src/launchstatestore.h
    src/keyvaluelist.h
    src/favoritesfolderlogic.cpp
    src/favoritesfolderlogic.h
    src/abstractgroupedmodel.cpp
    src/abstractgroupedmodel.h
    src/favoritesgroupedmodel.cpp
    src/favoritesgroupedmodel.h
    src/menuscanner.cpp
    src/menuscanner.h
    src/menutree.cpp
    src/menutree.h
    src/menutreemodel.cpp
    src/menutreemodel.h
    src/menutreesource.cpp
    src/menutreesource.h
    src/runnerfiltermodel.cpp
    src/runnerfiltermodel.h
    src/unifiedsearchmodel.cpp
    src/unifiedsearchmodel.h
    src/frecencyprovider.cpp
    src/frecencyprovider.h
    src/usedappsprovider.cpp
    src/usedappsprovider.h
    src/newappstracker.cpp
    src/newappstracker.h
    src/windowconfigurator.cpp
    src/windowconfigurator.h
    src/frecencyscoring.cpp
    src/frecencyscoring.h
)
# Update checker is compiled in only for universal-tarball builds.
if(APPGRID_UNIVERSAL_BUILD)
    list(APPEND APPGRID_COMMON_SOURCES src/updatechecker.cpp src/updatechecker.h)
endif()

# Build an AppGrid variant as a compiled-QML Plasma applet (#173): the QML is
# baked into the .so as PLAIN qrc resources at the root Plasma::Applet::qrcPath()
# expects (:/qt/qml/plasma/applet/<pluginId with / for .>/), with main.qml at the
# root. It is NOT a registered QML module — Plasma loads main.qml as a qrc file
# and the relative/directory imports (import "controllers", "../js/x.js") resolve
# from the resource at runtime. Keeping the QML as source (no qmlcachegen/AOT)
# avoids the QTP0004 qmldir requirement and stays version-portable. The applet
# metadata is embedded Id-free (pluginId derives from the filename), which is
# what silences the KCoreAddons "explicitly states an Id" warning.
function(appgrid_add_compiled_applet)
    cmake_parse_arguments(A "" "TARGET;VARIANT;METADATA" "SOURCES" ${ARGN})

    add_library(${A_TARGET} SHARED ${A_SOURCES})
    set_target_properties(${A_TARGET} PROPERTIES PREFIX ""
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/plasma/applets")
    target_link_libraries(${A_TARGET} PRIVATE ${APPGRID_COMMON_LIBS})
    target_compile_definitions(${A_TARGET} PRIVATE
        "APPGRID_VERSION=\"${APPGRID_VERSION_STRING}\""
        "TRANSLATION_DOMAIN=\"${APPGRID_APP_ID}\""
        "APPGRID_APP_ID=\"${APPGRID_APP_ID}\"")
    if(ENABLE_X11)
        target_compile_definitions(${A_TARGET} PRIVATE APPGRID_X11_SUPPORT)
    endif()
    if(APPGRID_UNIVERSAL_BUILD)
        target_link_libraries(${A_TARGET} PRIVATE Qt6::Network)
        target_compile_definitions(${A_TARGET} PRIVATE APPGRID_UNIVERSAL_BUILD)
    endif()
    if(APPGRID_DBUS_ACTIVATION)
        target_compile_definitions(${A_TARGET} PRIVATE APPGRID_DBUS_ACTIVATION)
    endif()
    if(APPGRID_STRICT_WARNINGS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        set(_w -Wall -Wextra -Wunused -Wshadow -Wnon-virtual-dtor -Werror)
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            list(APPEND _w -Wunreachable-code-aggressive)
        endif()
        target_compile_options(${A_TARGET} PRIVATE ${_w})
    endif()

    # qrc prefix mirrors Applet::qrcPath(): the pluginId (= the .so/target name)
    # with dots replaced by slashes.
    string(REPLACE "." "/" _idpath ${A_TARGET})
    set(_prefix "/qt/qml/plasma/applet/${_idpath}")
    set(_files)
    # Entry + compact rep from the variant → qrc root.
    foreach(_f main.qml CompactRepresentation.qml)
        set(_s ${CMAKE_CURRENT_SOURCE_DIR}/package/variants/${A_VARIANT}/${_f})
        set_source_files_properties(${_s} PROPERTIES QT_RESOURCE_ALIAS ${_f})
        list(APPEND _files ${_s})
    endforeach()
    # Plasma config entry + KConfigXT schema → qrc root (the flat layout Plasma's
    # compiled applets use; config.qml's "config/Foo.qml" sources resolve under it).
    # The config model is per-variant: config-<variant>.qml aliased to config.qml
    # when present (the center variant trims it to the panel button, the launcher
    # being configured from the daemon's own window), else the shared config.qml.
    set(_cfg ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/config/config-${A_VARIANT}.qml)
    if(NOT EXISTS ${_cfg})
        set(_cfg ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/config/config.qml)
    endif()
    set_source_files_properties(${_cfg} PROPERTIES QT_RESOURCE_ALIAS config.qml)
    list(APPEND _files ${_cfg})
    set(_xml ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/config/main.xml)
    set_source_files_properties(${_xml} PROPERTIES QT_RESOURCE_ALIAS main.xml)
    list(APPEND _files ${_xml})
    # Shared QML/JS under contents/ui/ → alias = path relative to contents/ui/,
    # preserving the subdir structure so the relative imports keep resolving.
    file(GLOB_RECURSE _ui CONFIGURE_DEPENDS
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/*.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/*.js)
    foreach(_s ${_ui})
        file(RELATIVE_PATH _alias ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui ${_s})
        set_source_files_properties(${_s} PROPERTIES QT_RESOURCE_ALIAS ${_alias})
        list(APPEND _files ${_s})
    endforeach()
    qt_add_resources(${A_TARGET} "${A_TARGET}_qml" PREFIX ${_prefix} FILES ${_files})

    # Embedded applet metadata, configured from the template (which carries no
    # KPlugin Id — the pluginId derives from the .so filename, so an explicit Id
    # would make KCoreAddons warn, #173). The embedded file is named
    # metadata-<variant>.json to match its K_PLUGIN_CLASS_WITH_JSON literal, so
    # moc can never resolve a different variant's metadata (or a stray
    # "metadata.json" left in a build tree) — a bare shared name was fragile
    # against moc's source-dir-first include resolution. The per-target embed
    # dir stays on the moc path.
    set(_embed ${CMAKE_BINARY_DIR}/embed/${A_TARGET})
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/${A_METADATA} ${_embed}/metadata-${A_VARIANT}.json @ONLY)
    set_property(TARGET ${A_TARGET} APPEND PROPERTY AUTOMOC_MOC_OPTIONS "-I${_embed}")

    install(TARGETS ${A_TARGET} DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
endfunction()

# --- Center variant (custom Window with centered popup) ---
appgrid_add_compiled_applet(
    TARGET dev.xarbit.appgrid
    VARIANT center
    METADATA metadata.json.in
    SOURCES src/appgridplugin_register.cpp ${APPGRID_COMMON_SOURCES})

# --- Panel plasmoid (native Plasma popup near panel icon) ---
appgrid_add_compiled_applet(
    TARGET dev.xarbit.appgrid.panel
    VARIANT panel
    METADATA metadata-panel.json.in
    SOURCES src/appgridpanelplugin.cpp src/appgridpanelplugin.h
            src/popupsizepolicy.cpp src/popupsizepolicy.h ${APPGRID_COMMON_SOURCES})

# --- Standalone executable (own process → KWin window open/close effects) ---
# A plasmoid window lives in plasmashell, which KWin's Glide/Scale effects
# exclude. A separate `appgrid` binary gives the window class "appgrid", so it
# animates like KRunner. Reuses the common sources + the controller, plus a
# KConfigXT config class generated from the SAME schema the applet uses.

# Generate the standalone .kcfg from the applet's config/main.xml so the two
# never drift: identical entries, only the backing file name differs.
set(_appgrid_kcfg ${CMAKE_BINARY_DIR}/appgridconfig.kcfg)
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/config/main.xml _appgrid_main_xml)
string(REPLACE "<kcfgfile name=\"\"/>" "<kcfgfile name=\"appgridrc\"/>" _appgrid_main_xml "${_appgrid_main_xml}")
file(WRITE ${_appgrid_kcfg} "${_appgrid_main_xml}")
# The .kcfgc's File= points at this generated .kcfg (resolved against the .kcfgc
# location); copy it next to the generated schema so kconfig_add_kcfg_files
# finds both in the build dir.
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/standalone/appgridconfig.kcfgc
               ${CMAKE_BINARY_DIR}/appgridconfig.kcfgc COPYONLY)

set(APPGRID_STANDALONE_SOURCES
    src/standalone/main.cpp
    src/standalone/appgridstandalone.cpp
    src/standalone/appgridstandalone.h
    ${APPGRID_COMMON_SOURCES})

add_executable(appgrid ${APPGRID_STANDALONE_SOURCES})
kconfig_add_kcfg_files(appgrid GENERATE_MOC ${CMAKE_BINARY_DIR}/appgridconfig.kcfgc)
target_include_directories(appgrid PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
# KF6::ConfigGui supplies KConfigSkeleton (the generated AppGridConfig base);
# Widgets gives the KDE platform palette, QuickControls2 the org.kde.desktop style.
target_link_libraries(appgrid PRIVATE ${APPGRID_COMMON_LIBS} KF6::ConfigGui Qt6::Widgets Qt6::QuickControls2 KF6::ColorScheme KF6::I18nQml)
target_compile_definitions(appgrid PRIVATE
    "APPGRID_VERSION=\"${APPGRID_VERSION_STRING}\""
    "TRANSLATION_DOMAIN=\"${APPGRID_APP_ID}\""
    "APPGRID_APP_ID=\"${APPGRID_APP_ID}\"")
if(ENABLE_X11)
    target_compile_definitions(appgrid PRIVATE APPGRID_X11_SUPPORT)
endif()
if(APPGRID_UNIVERSAL_BUILD)
    target_link_libraries(appgrid PRIVATE Qt6::Network)
    target_compile_definitions(appgrid PRIVATE APPGRID_UNIVERSAL_BUILD)
endif()
if(APPGRID_STRICT_WARNINGS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set(_w -Wall -Wextra -Wunused -Wshadow -Wnon-virtual-dtor -Werror)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        list(APPEND _w -Wunreachable-code-aggressive)
    endif()
    target_compile_options(appgrid PRIVATE ${_w})
endif()

# Bundle the shared QML the same way the applet does, but under a private prefix
# the executable loads from. main.qml sits as a sibling of views/, controllers/,
# js/ so its relative imports ("controllers", "../js/x.js", GridPanel, …)
# resolve identically to the applet.
set(_appgrid_qml_prefix "/qt/qml/appgrid")
set(_appgrid_qml_files)
set(_appgrid_entry ${CMAKE_CURRENT_SOURCE_DIR}/package/standalone/main.qml)
set_source_files_properties(${_appgrid_entry} PROPERTIES QT_RESOURCE_ALIAS Main.qml)
list(APPEND _appgrid_qml_files ${_appgrid_entry})
set(_appgrid_cfgwin ${CMAKE_CURRENT_SOURCE_DIR}/package/standalone/ConfigWindow.qml)
set_source_files_properties(${_appgrid_cfgwin} PROPERTIES QT_RESOURCE_ALIAS ConfigWindow.qml)
list(APPEND _appgrid_qml_files ${_appgrid_cfgwin})
file(GLOB_RECURSE _appgrid_ui CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/*.qml
    ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/*.js)
foreach(_s ${_appgrid_ui})
    file(RELATIVE_PATH _alias ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui ${_s})
    set_source_files_properties(${_s} PROPERTIES QT_RESOURCE_ALIAS ${_alias})
    list(APPEND _appgrid_qml_files ${_s})
endforeach()
qt_add_resources(appgrid "appgrid_standalone_qml" PREFIX ${_appgrid_qml_prefix} FILES ${_appgrid_qml_files})

install(TARGETS appgrid DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES dev.xarbit.appgrid.desktop DESTINATION ${KDE_INSTALL_APPDIR})

# On-demand activation: a D-Bus service file delegates to a Type=dbus systemd
# user unit (KRunner's model). A method call to dev.xarbit.appgrid then starts
# the installed build with --daemon and delivers the call. @KDE_INSTALL_FULL_BINDIR@
# bakes the absolute Exec path, which is why this is off for the relocatable
# universal build (the plasmoid falls back to launching the binary explicitly).
if(APPGRID_DBUS_ACTIVATION)
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/dev.xarbit.appgrid.service.in
                   ${CMAKE_BINARY_DIR}/dev.xarbit.appgrid.service @ONLY)
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/appgrid.service.in
                   ${CMAKE_BINARY_DIR}/appgrid.service @ONLY)
    install(FILES ${CMAKE_BINARY_DIR}/dev.xarbit.appgrid.service
            DESTINATION ${KDE_INSTALL_DBUSSERVICEDIR})
    install(FILES ${CMAKE_BINARY_DIR}/appgrid.service
            DESTINATION ${KDE_INSTALL_SYSTEMDUSERUNITDIR})
endif()

message(STATUS "AppGrid ENABLE_X11=${ENABLE_X11}")

# --- Common ---

ki18n_install(po)

install(FILES dev.xarbit.appgrid.metainfo.xml
        DESTINATION ${KDE_INSTALL_METAINFODIR})

install(FILES dev.xarbit.appgrid.svg
        DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# Global launcher shortcut, plasmoid-independent (#195): kglobalacceld reads this
# at session start so "Open AppGrid" / "Open in Compact Mode" appear in System
# Settings → Shortcuts and work without the applet on a panel — KRunner's model.
# Installed under a DISTINCT component id (…​.launcher) so it does not merge into
# the plasmoid applet's own component (dev.xarbit.appgrid, which Plasma files
# under "System Services"); a separate Type=Application component lands the
# launcher shortcut under "Applications", beside KRunner.
install(FILES dev.xarbit.appgrid.kglobalaccel.desktop
        DESTINATION ${KDE_INSTALL_DATAROOTDIR}/kglobalaccel
        RENAME dev.xarbit.appgrid.launcher.desktop)

# Pre-warm the launcher daemon at login (KRunner's "warm at login" behaviour):
# `appgrid --daemon` starts resident without a window, so the first open is
# instant instead of a cold start. Shipped enabled; users toggle it in System
# Settings → Autostart. An XDG autostart entry (not a systemd target hook) so it
# also covers the universal build, where D-Bus activation is compiled out.
install(FILES dev.xarbit.appgrid.autostart.desktop
        DESTINATION ${KDE_INSTALL_SYSCONFDIR}/xdg/autostart)

# --- Tests ---

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
