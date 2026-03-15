# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.20)
project(AppGrid VERSION 1.0.0 LANGUAGES CXX)

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

# --- Plasma applet C++ plugin ---
add_library(dev.xarbit.appgrid SHARED
    src/appgridplugin.cpp
    src/appgridplugin.h
    src/appmodel.cpp
    src/appmodel.h
)

set_target_properties(dev.xarbit.appgrid PROPERTIES PREFIX "")

target_link_libraries(dev.xarbit.appgrid PRIVATE
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

# Copy metadata.json next to source for K_PLUGIN_CLASS_WITH_JSON
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/package/metadata.json
    ${CMAKE_CURRENT_SOURCE_DIR}/src/metadata.json
    COPYONLY
)

# --- Install ---
install(TARGETS dev.xarbit.appgrid DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)

plasma_install_package(package dev.xarbit.appgrid)

ki18n_install(po)

install(FILES dev.xarbit.appgrid.metainfo.xml
        DESTINATION ${KDE_INSTALL_METAINFODIR})
