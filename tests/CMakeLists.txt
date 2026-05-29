# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Test)

set(TEST_COMMON_SOURCES
    ${CMAKE_SOURCE_DIR}/src/appmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/appfiltermodel.cpp
    ${CMAKE_SOURCE_DIR}/src/categorymapping.cpp
    ${CMAKE_SOURCE_DIR}/src/runnerfiltermodel.cpp
    ${CMAKE_SOURCE_DIR}/src/unifiedsearchmodel.cpp
)

set(TEST_COMMON_LIBS
    Qt6::Test
    Qt6::Gui
    KF6::Service
    KF6::I18n
    KF6::CoreAddons
    KF6::KIOGui
    KF6::IconThemes
)

include_directories(${CMAKE_SOURCE_DIR}/src)

# Helper: defines a Qt test executable and registers it with CTest.
# Pass extra headers (e.g. Q_OBJECT-containing helpers) as ARGN so AUTOMOC
# generates moc files for them.
function(appgrid_add_test name)
    add_executable(${name} ${name}.cpp ${TEST_COMMON_SOURCES} ${ARGN})
    target_link_libraries(${name} PRIVATE ${TEST_COMMON_LIBS})
    add_test(NAME ${name} COMMAND ${name})
endfunction()

appgrid_add_test(test_appfiltermodel ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h)
appgrid_add_test(test_search_ranking ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h)
appgrid_add_test(test_filter ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h)
appgrid_add_test(test_sort ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h)
appgrid_add_test(test_runner_filter ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h
    ${CMAKE_SOURCE_DIR}/src/runnerfiltermodel.h)
appgrid_add_test(test_unified_search ${CMAKE_CURRENT_SOURCE_DIR}/stubappmodel.h
    ${CMAKE_SOURCE_DIR}/src/runnerfiltermodel.h
    ${CMAKE_SOURCE_DIR}/src/unifiedsearchmodel.h)
appgrid_add_test(test_appmodel_helpers)
appgrid_add_test(test_category_mapping
    ${CMAKE_SOURCE_DIR}/src/categorymapping.h)
# Regression test for issues #86 (icon file change on disk) and #103
# (system theme switch). Both flow through KIconLoader::iconChanged.
appgrid_add_test(test_appmodel)

# Pure helpers extracted from AppGridPlugin — no Plasma deps, so a light
# standalone target instead of the model-heavy appgrid_add_test().
add_executable(test_pluginhelpers
    test_pluginhelpers.cpp
    ${CMAKE_SOURCE_DIR}/src/pluginhelpers.cpp
    ${CMAKE_SOURCE_DIR}/src/pluginhelpers.h
)
target_link_libraries(test_pluginhelpers PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_pluginhelpers COMMAND test_pluginhelpers)

# UpdateChecker only exists in universal builds; gate the test to match so
# distro-package CI runs (which don't compile updatechecker.cpp) don't try
# to link against missing symbols.
if(APPGRID_UNIVERSAL_BUILD)
    find_package(Qt6 REQUIRED COMPONENTS Network)
    add_executable(test_updatechecker
        test_updatechecker.cpp
        ${CMAKE_SOURCE_DIR}/src/updatechecker.cpp
        ${CMAKE_SOURCE_DIR}/src/updatechecker.h
    )
    target_link_libraries(test_updatechecker PRIVATE
        Qt6::Test Qt6::Core Qt6::Gui Qt6::Network)
    target_compile_definitions(test_updatechecker PRIVATE
        APPGRID_UNIVERSAL_BUILD
        "APPGRID_VERSION=\"${APPGRID_VERSION_STRING}\"")
    add_test(NAME test_updatechecker COMMAND test_updatechecker)
endif()

# --- QML tests (QtQuickTest) ---

find_package(Qt6 OPTIONAL_COMPONENTS QuickTest Quick Qml)

if(Qt6QuickTest_FOUND)
    # Copy QML components next to the tests so they can be loaded relatively.
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/PrefixDetector.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/PrefixDetector.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/MnemonicResolver.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/MnemonicResolver.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/HoverGate.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/HoverGate.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/favoriteid.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/favoriteid.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/migrations.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/migrations.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/SelectionState.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/SelectionState.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/VisibilityState.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/VisibilityState.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/SearchSessionManager.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/SearchSessionManager.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/scrolleasing.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/scrolleasing.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/favoritesmigration.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/favoritesmigration.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/headeractions.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/headeractions.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/searchresultnav.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/searchresultnav.js
        COPYONLY
    )

    add_executable(tst_qml qml/main.cpp)
    target_link_libraries(tst_qml PRIVATE Qt6::QuickTest Qt6::Quick Qt6::Qml Qt6::Core)
    target_compile_definitions(tst_qml PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
    add_test(NAME tst_qml COMMAND tst_qml)
else()
    message(STATUS "Qt6QuickTest not found — skipping QML tests")
endif()
