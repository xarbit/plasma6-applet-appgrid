# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.8.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

# X11 support — disable when targeting Plasma 6.8+ (Wayland-only)
option(ENABLE_X11 "Enable X11 session support" ON)

option(BUILD_TESTING "Build the test suite" OFF)

# Universal-build flag — enables the in-app update checker (notify-only,
# opt-in via config). Distros that ship via their package manager should
# leave this OFF so the package manager remains the source of truth for
# updates. The universal tarball CI job turns it ON.
option(APPGRID_UNIVERSAL_BUILD "Compile in the in-app update checker for universal tarball releases" OFF)

# Resolved version baked into the binary (update checker + i: view):
#   1. APPGRID_VERSION_OVERRIDE wins (CI injects exact tag here).
#   2. On a release tag → CMAKE_PROJECT_VERSION (clean "1.8.0").
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
find_package(KF6Service REQUIRED)
find_package(KF6I18n REQUIRED)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Package REQUIRED)
find_package(KF6IconThemes REQUIRED)
find_package(LayerShellQt REQUIRED)
# LibKWorkspace no longer required — session actions use Kicker.SystemModel
# find_package(LibKWorkspace REQUIRED)
find_package(KF6Runner REQUIRED)
find_package(Plasma REQUIRED)
find_package(PlasmaQuick REQUIRED)
# Write-side only: KActivities::ResourceInstance::notifyAccessed broadcasts
# AppGrid launches to the system-wide KActivities database so Kickoff / KRunner /
# Plasma Activities see AppGrid as a contributing launcher. We do NOT read from
# KActivities — see #95 close-out for the rationale.
find_package(PlasmaActivities REQUIRED)

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
    LayerShellQt::Interface
    Plasma::PlasmaQuick
    KF6::Runner
    Plasma::Activities
)

# QML components shared between both plasmoids
set(SHARED_QML_FILES
    AppContextMenu.qml
    AppGridView.qml
    AppIconDelegate.qml
    CategoryBar.qml
    CategoryGridView.qml
    DragSource.qml
    EdgeAutoScroller.qml
    FavoritesReorderArea.qml
    FavoritesTabDragHover.qml
    KeyboardShortcuts.qml
    favoriteid.js
    SharedFavoritesProvider.qml
    GridPanel.qml
    MnemonicResolver.qml
    PowerButtons.qml
    PrefixDetector.qml
    PrefixModeView.qml
    RecentAppsHeader.qml
    SearchBar.qml
    SearchResultsList.qml
    SelectionState.qml
    ShuffleOverlay.qml
)

set(SHARED_PREFIX_QML_FILES
    prefix/PrefixHelpView.qml
    prefix/PrefixCommandView.qml
    prefix/PrefixInfoView.qml
    prefix/PrefixHiddenView.qml
    prefix/PrefixFileBrowser.qml
)

set(SHARED_ICONANIM_QML_FILES
    iconanims/ShakeAnim.qml
    iconanims/GrowAnim.qml
    iconanims/BounceAnim.qml
    iconanims/SpinAnim.qml
)

# --- Main plasmoid (Center variant: custom Window with centered popup) ---

set(APPGRID_SOURCES
    src/appgridplugin_register.cpp
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
    src/appfiltermodel.cpp
    src/appfiltermodel.h
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
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata.json.in
    ${CMAKE_CURRENT_SOURCE_DIR}/package/metadata.json
    @ONLY
)

install(TARGETS dev.xarbit.appgrid DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
plasma_install_package(package dev.xarbit.appgrid)

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

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata-panel.json.in
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata-panel.json
    @ONLY
)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/metadata-panel.json.in
    ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/metadata.json
    @ONLY
)

# Copy shared QML components into the popup package at build time
foreach(qml_file ${SHARED_QML_FILES})
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/${qml_file}
        ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/contents/ui/${qml_file}
        COPYONLY
    )
endforeach()

foreach(qml_file ${SHARED_PREFIX_QML_FILES})
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/${qml_file}
        ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/contents/ui/${qml_file}
        COPYONLY
    )
endforeach()

foreach(qml_file ${SHARED_ICONANIM_QML_FILES})
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/${qml_file}
        ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/contents/ui/${qml_file}
        COPYONLY
    )
endforeach()

install(TARGETS dev.xarbit.appgrid.panel DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
plasma_install_package(package-panel dev.xarbit.appgrid.panel)

# --- Dev flags ---
# Read BUILDFLAGS file and parse key=value pairs

set(DEV_MODE "false")
set(DEV_EXTRA_CATEGORIES "false")

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/BUILDFLAGS")
    file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/BUILDFLAGS" _flag_lines)
    foreach(_line ${_flag_lines})
        # Skip comments and empty lines
        string(REGEX MATCH "^[A-Z_]+=.+" _match "${_line}")
        if(_match)
            string(REGEX REPLACE "^([A-Z_]+)=(.+)" "\\1;\\2" _parts "${_line}")
            list(GET _parts 0 _key)
            list(GET _parts 1 _val)
            set(${_key} "${_val}")
        endif()
    endforeach()
endif()

# Only enable individual flags if DEV_MODE is true
if(NOT DEV_MODE STREQUAL "true")
    set(DEV_EXTRA_CATEGORIES "false")
endif()

message(STATUS "AppGrid DEV_MODE=${DEV_MODE}")
message(STATUS "AppGrid DEV_EXTRA_CATEGORIES=${DEV_EXTRA_CATEGORIES}")
message(STATUS "AppGrid ENABLE_X11=${ENABLE_X11}")

# Generate DevFlags.qml from template
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/DevFlags.qml.in
    ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/DevFlags.qml
    @ONLY
)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/DevFlags.qml.in
    ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/contents/ui/DevFlags.qml
    @ONLY
)

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
