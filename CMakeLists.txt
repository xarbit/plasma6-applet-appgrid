# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.7.7 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

# X11 support — disable when targeting Plasma 6.8+ (Wayland-only)
option(ENABLE_X11 "Enable X11 session support" ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Gui DBus)
find_package(KF6Service REQUIRED)
find_package(KF6I18n REQUIRED)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Package REQUIRED)
find_package(LayerShellQt REQUIRED)
# LibKWorkspace no longer required — session actions use Kicker.SystemModel
# find_package(LibKWorkspace REQUIRED)
find_package(KF6Runner REQUIRED)
find_package(Plasma REQUIRED)
find_package(PlasmaQuick REQUIRED)

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
    LayerShellQt::Interface
    Plasma::PlasmaQuick
    KF6::Runner
)

# QML components shared between both plasmoids
set(SHARED_QML_FILES
    AppContextMenu.qml
    AppGridView.qml
    AppIconDelegate.qml
    CategoryBar.qml
    CategoryGridView.qml
    GridPanel.qml
    PowerButtons.qml
    PrefixModeView.qml
    RecentAppsHeader.qml
    SearchBar.qml
    SearchResultsList.qml
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

# --- Main plasmoid (custom Window: fullscreen/centered) ---

add_library(dev.xarbit.appgrid SHARED
    src/appgridplugin_register.cpp
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
    src/appfiltermodel.cpp
    src/appfiltermodel.h
)
set_target_properties(dev.xarbit.appgrid PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid PRIVATE ${APPGRID_COMMON_LIBS})
if(ENABLE_X11)
    target_compile_definitions(dev.xarbit.appgrid PRIVATE APPGRID_X11_SUPPORT)
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

add_library(dev.xarbit.appgrid.panel SHARED
    src/appgridpanelplugin.cpp
    src/appgridpanelplugin.h
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
    src/appfiltermodel.cpp
    src/appfiltermodel.h
)
set_target_properties(dev.xarbit.appgrid.panel PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid.panel PRIVATE ${APPGRID_COMMON_LIBS})
if(ENABLE_X11)
    target_compile_definitions(dev.xarbit.appgrid.panel PRIVATE APPGRID_X11_SUPPORT)
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
