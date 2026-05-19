# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Test)

# Each test executable re-compiles the minimum source set it needs rather
# than depending on the plasmoid SHARED libraries — those are QML plugins
# without a stable C++ API surface and dragging them in here would pull
# the entire QML registration code into the test process.

add_executable(appmodeltest
    appmodeltest.cpp
    ../appmodel.cpp
    ../appmodel.h
)
target_include_directories(appmodeltest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(appmodeltest PRIVATE
    Qt6::Test
    Qt6::Gui
    Qt6::DBus
    KF6::Service
    KF6::I18n
    KF6::CoreAddons
    KF6::KIOGui
    KF6::IconThemes
)
add_test(NAME appmodeltest COMMAND appmodeltest)
