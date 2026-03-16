# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.2.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Gui DBus)
find_package(KF6Service REQUIRED)
find_package(KF6I18n REQUIRED)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Package REQUIRED)
find_package(LayerShellQt REQUIRED)
find_package(LibKWorkspace REQUIRED)
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
    PW::KWorkspace
    Plasma::PlasmaQuick
)

# QML components shared between both plasmoids
set(SHARED_QML_FILES
    AppContextMenu.qml
    AppGridView.qml
    AppIconDelegate.qml
    CategoryBar.qml
    GridPanel.qml
    PowerButtons.qml
    PrefixModeView.qml
    RecentAppsHeader.qml
    SearchBar.qml
    SearchResultsList.qml
    ShuffleOverlay.qml
)

# --- Main plasmoid (custom Window: fullscreen/centered) ---

add_library(dev.xarbit.appgrid SHARED
    src/appgridplugin_register.cpp
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
)
set_target_properties(dev.xarbit.appgrid PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid PRIVATE ${APPGRID_COMMON_LIBS})

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/package/metadata.json
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata.json
    COPYONLY
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
)
set_target_properties(dev.xarbit.appgrid.panel PROPERTIES PREFIX "")
target_link_libraries(dev.xarbit.appgrid.panel PRIVATE ${APPGRID_COMMON_LIBS})

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/metadata.json
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata-panel.json
    COPYONLY
)

# Copy shared QML components into the popup package at build time
foreach(qml_file ${SHARED_QML_FILES})
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui/${qml_file}
        ${CMAKE_CURRENT_SOURCE_DIR}/package-panel/contents/ui/${qml_file}
        COPYONLY
    )
endforeach()

install(TARGETS dev.xarbit.appgrid.panel DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)
plasma_install_package(package-panel dev.xarbit.appgrid.panel)

# --- Common ---

ki18n_install(po)

install(FILES dev.xarbit.appgrid.metainfo.xml
        DESTINATION ${KDE_INSTALL_METAINFODIR})
