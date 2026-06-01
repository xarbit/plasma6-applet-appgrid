# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.9.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# ECM ships KDEInstallDirs, which defines the KDE_INSTALL_* paths this build
# installs into. Include it before find_package(Qt6) — Qt pulls in
# GNUInstallDirs, and if that runs first the KDE_INSTALL_* dirs get shadowed
# by CMAKE_INSTALL_*, which ECM warns about.
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

# X11 support — disable when targeting Plasma 6.8+ (Wayland-only)
option(ENABLE_X11 "Enable X11 session support" ON)

option(BUILD_TESTING "Build the test suite" OFF)

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

find_package(Qt6 REQUIRED COMPONENTS Quick Gui DBus)
if(APPGRID_UNIVERSAL_BUILD)
    find_package(Qt6 REQUIRED COMPONENTS Network)
endif()
# KF6 floor matches the oldest Plasma 6 desktop we still ship for
# (Plasma 6.0 → KF6 6.0). Newer APIs must be gated behind explicit
# version checks rather than raising this minimum.
set(KF6_MIN_VERSION 6.0)
find_package(KF6Service ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6I18n ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6CoreAddons ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6KIO ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6WindowSystem ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6Package ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6IconThemes ${KF6_MIN_VERSION} REQUIRED)
find_package(KF6GlobalAccel ${KF6_MIN_VERSION} REQUIRED)
find_package(LayerShellQt REQUIRED)
find_package(KF6Runner ${KF6_MIN_VERSION} REQUIRED)
find_package(Plasma REQUIRED)
find_package(PlasmaQuick REQUIRED)
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
    KF6::Service
    KF6::I18n
    KF6::CoreAddons
    KF6::KIOGui
    KF6::WindowSystem
    KF6::IconThemes
    KF6::GlobalAccel
    LayerShellQt::Interface
    Plasma::PlasmaQuick
    KF6::Runner
    Plasma::Activities
    Plasma::ActivitiesStats
    AppStreamQt
)

# Assemble a complete plasmoid package for ${variant} under the build tree
# from the single package/ source: the entire shared base (package/contents/)
# plus the variant-only entry files in package/variants/${variant}/, which
# mirror their contents/ui/ destination paths.
#
# Both variants share all of contents/ and differ only in the entry files
# (main.qml + its compact representation), which live outside contents/ under
# variants/. So the base is globbed wholesale rather than enumerated: a new
# shared QML file (or whole folder, e.g. animations/) is staged automatically,
# with no list to forget.
#
# Each variant is staged into its own tree because plasma_install_package()
# ships a whole directory — installing package/ in place would leak every
# variant's entry files into every plasmoid. Adding a variant = a new
# package/variants/<name>/ folder plus a stage+install pair below.
function(appgrid_stage_variant dest variant)
    set(_base ${CMAKE_CURRENT_SOURCE_DIR}/package/contents)
    file(GLOB_RECURSE _shared_files RELATIVE ${_base} CONFIGURE_DEPENDS ${_base}/*)
    foreach(shared_file ${_shared_files})
        configure_file(${_base}/${shared_file} ${dest}/contents/${shared_file} COPYONLY)
    endforeach()

    set(_variant_dir ${CMAKE_CURRENT_SOURCE_DIR}/package/variants/${variant})
    file(GLOB_RECURSE _entry_files RELATIVE ${_variant_dir} CONFIGURE_DEPENDS ${_variant_dir}/*)
    foreach(entry_file ${_entry_files})
        configure_file(${_variant_dir}/${entry_file} ${dest}/contents/ui/${entry_file} COPYONLY)
    endforeach()
endfunction()

# --- Main plasmoid (Center variant: custom Window with centered popup) ---

set(APPGRID_SOURCES
    src/appgridplugin_register.cpp
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
    src/appfiltermodel.cpp
    src/appfiltermodel.h
    src/categorymapping.cpp
    src/categorymapping.h
    src/pluginhelpers.cpp
    src/pluginhelpers.h
    src/runnerfiltermodel.cpp
    src/runnerfiltermodel.h
    src/unifiedsearchmodel.cpp
    src/unifiedsearchmodel.h
    src/frecencyprovider.cpp
    src/frecencyprovider.h
)
if(APPGRID_UNIVERSAL_BUILD)
    list(APPEND APPGRID_SOURCES src/updatechecker.cpp src/updatechecker.h)
endif()

add_library(dev.xarbit.appgrid SHARED ${APPGRID_SOURCES})
set_target_properties(dev.xarbit.appgrid PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid PRIVATE ${APPGRID_COMMON_LIBS})
target_compile_definitions(dev.xarbit.appgrid PRIVATE
    "APPGRID_VERSION=\"${APPGRID_VERSION_STRING}\"")
if(ENABLE_X11)
    target_compile_definitions(dev.xarbit.appgrid PRIVATE APPGRID_X11_SUPPORT)
endif()
if(APPGRID_UNIVERSAL_BUILD)
    target_link_libraries(dev.xarbit.appgrid PRIVATE Qt6::Network)
    target_compile_definitions(dev.xarbit.appgrid PRIVATE APPGRID_UNIVERSAL_BUILD)
endif()

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata.json.in
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata.json
    @ONLY
)

set(APPGRID_CENTER_PACKAGE ${CMAKE_BINARY_DIR}/package-center)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata.json.in
    ${APPGRID_CENTER_PACKAGE}/metadata.json
    @ONLY
)
appgrid_stage_variant(${APPGRID_CENTER_PACKAGE} center)

install(TARGETS dev.xarbit.appgrid DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
plasma_install_package(${APPGRID_CENTER_PACKAGE} dev.xarbit.appgrid)

# --- Panel plasmoid (native Plasma popup near panel icon) ---

set(APPGRID_PANEL_SOURCES
    src/appgridpanelplugin.cpp
    src/appgridpanelplugin.h
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
    src/appfiltermodel.cpp
    src/appfiltermodel.h
    src/categorymapping.cpp
    src/categorymapping.h
    src/pluginhelpers.cpp
    src/pluginhelpers.h
    src/runnerfiltermodel.cpp
    src/runnerfiltermodel.h
    src/unifiedsearchmodel.cpp
    src/unifiedsearchmodel.h
    src/frecencyprovider.cpp
    src/frecencyprovider.h
)
if(APPGRID_UNIVERSAL_BUILD)
    list(APPEND APPGRID_PANEL_SOURCES src/updatechecker.cpp src/updatechecker.h)
endif()

add_library(dev.xarbit.appgrid.panel SHARED ${APPGRID_PANEL_SOURCES})
set_target_properties(dev.xarbit.appgrid.panel PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid.panel PRIVATE ${APPGRID_COMMON_LIBS})
target_compile_definitions(dev.xarbit.appgrid.panel PRIVATE
    "APPGRID_VERSION=\"${APPGRID_VERSION_STRING}\"")
if(ENABLE_X11)
    target_compile_definitions(dev.xarbit.appgrid.panel PRIVATE APPGRID_X11_SUPPORT)
endif()
if(APPGRID_UNIVERSAL_BUILD)
    target_link_libraries(dev.xarbit.appgrid.panel PRIVATE Qt6::Network)
    target_compile_definitions(dev.xarbit.appgrid.panel PRIVATE APPGRID_UNIVERSAL_BUILD)
endif()

if(APPGRID_STRICT_WARNINGS AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set(_appgrid_warnings -Wall -Wextra -Wunused -Wshadow -Wnon-virtual-dtor -Werror)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        list(APPEND _appgrid_warnings -Wunreachable-code-aggressive)
    endif()
    foreach(_tgt dev.xarbit.appgrid dev.xarbit.appgrid.panel)
        target_compile_options(${_tgt} PRIVATE ${_appgrid_warnings})
    endforeach()
endif()

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata-panel.json.in
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata-panel.json
    @ONLY
)

set(APPGRID_PANEL_PACKAGE ${CMAKE_BINARY_DIR}/package-panel)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata-panel.json.in
    ${APPGRID_PANEL_PACKAGE}/metadata.json
    @ONLY
)
appgrid_stage_variant(${APPGRID_PANEL_PACKAGE} panel)

install(TARGETS dev.xarbit.appgrid.panel DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
plasma_install_package(${APPGRID_PANEL_PACKAGE} dev.xarbit.appgrid.panel)

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
