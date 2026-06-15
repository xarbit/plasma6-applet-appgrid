# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.9.0 LANGUAGES CXX)

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

# Compiler warnings. Off by default so distro/makepkg builds stay quiet and a
# new compiler warning can never break a user's build. CI turns this ON to add
# -Wall/-Wextra -Werror, so warnings fail the pipeline instead.
option(APPGRID_STRICT_WARNINGS "Enable -Wall/-Wextra and treat warnings as errors (CI gate)" OFF)

# Resolved version baked into the binary (update checker + i: view):
#   1. APPGRID_VERSION_OVERRIDE wins (CI injects exact tag here).
#   2. On a release tag → CMAKE_PROJECT_VERSION (clean "1.9.0").
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
    GlobalAccel
    I18n
    IconThemes
    KIO
    Runner
    Service
    Svg
    WindowSystem
)
find_package(LayerShellQt REQUIRED)
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
    KF6::GlobalAccel
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
    src/discoverbackends.cpp
    src/discoverbackends.h
    src/pluginhelpers.cpp
    src/pluginhelpers.h
    src/searchranking.cpp
    src/searchranking.h
    src/launchbookkeeping.cpp
    src/launchbookkeeping.h
    src/runnerfiltermodel.cpp
    src/runnerfiltermodel.h
    src/unifiedsearchmodel.cpp
    src/unifiedsearchmodel.h
    src/frecencyprovider.cpp
    src/frecencyprovider.h
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
    foreach(_f config.qml main.xml)
        set(_s ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/config/${_f})
        set_source_files_properties(${_s} PROPERTIES QT_RESOURCE_ALIAS ${_f})
        list(APPEND _files ${_s})
    endforeach()
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

message(STATUS "AppGrid ENABLE_X11=${ENABLE_X11}")

# --- Common ---

ki18n_install(po)

install(FILES dev.xarbit.appgrid.metainfo.xml
        DESTINATION ${KDE_INSTALL_METAINFODIR})

install(FILES dev.xarbit.appgrid.svg
        DESTINATION ${KDE_INSTALL_ICONDIR}/hicolor/scalable/apps)

# --- Tests ---

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
