# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Test)

set(TEST_COMMON_SOURCES
    ${CMAKE_SOURCE_DIR}/src/appmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/appmodelassembly.cpp
    ${CMAKE_SOURCE_DIR}/src/appfiltermodel.cpp
    ${CMAKE_SOURCE_DIR}/src/defaultappsresolver.cpp
    ${CMAKE_SOURCE_DIR}/src/categorymapping.cpp
    ${CMAKE_SOURCE_DIR}/src/runnerfiltermodel.cpp
    ${CMAKE_SOURCE_DIR}/src/unifiedsearchmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/pluginhelpers.cpp
    ${CMAKE_SOURCE_DIR}/src/searchranking.cpp
    ${CMAKE_SOURCE_DIR}/src/launchbookkeeping.cpp
)

set(TEST_COMMON_LIBS
    Qt6::Test
    Qt6::Gui
    KF6::Service
    KF6::I18n
    KF6::CoreAddons
    KF6::KIOGui
    KF6::IconThemes
    KF6::Runner
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
target_link_libraries(test_pluginhelpers PRIVATE Qt6::Test Qt6::Core KF6::ConfigCore)
add_test(NAME test_pluginhelpers COMMAND test_pluginhelpers)

# LaunchBookkeeping is a plain value type (QtCore only) — light standalone
# target like test_pluginhelpers.
add_executable(test_launchbookkeeping
    test_launchbookkeeping.cpp
    ${CMAKE_SOURCE_DIR}/src/launchbookkeeping.cpp
    ${CMAKE_SOURCE_DIR}/src/launchbookkeeping.h
)
target_link_libraries(test_launchbookkeeping PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_launchbookkeeping COMMAND test_launchbookkeeping)

# FrecencyScoring — pure rank-scoring extracted from FrecencyProvider, free of
# KActivities so it tests with QtCore only (like the helpers above).
add_executable(test_frecency_scoring
    test_frecency_scoring.cpp
    ${CMAKE_SOURCE_DIR}/src/frecencyscoring.cpp
    ${CMAKE_SOURCE_DIR}/src/frecencyscoring.h
)
target_link_libraries(test_frecency_scoring PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_frecency_scoring COMMAND test_frecency_scoring)

# AppModelAssembly — pure dedup/merge/sort extracted from AppModel, free of
# KService so it tests with QtCore only.
add_executable(test_appmodel_assembly
    test_appmodel_assembly.cpp
    ${CMAKE_SOURCE_DIR}/src/appmodelassembly.cpp
    ${CMAKE_SOURCE_DIR}/src/appmodelassembly.h
)
target_link_libraries(test_appmodel_assembly PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_appmodel_assembly COMMAND test_appmodel_assembly)

# PopupSizePolicy — pure panel popup-size save/restore decisions, QtCore only.
add_executable(test_popup_size_policy
    test_popup_size_policy.cpp
    ${CMAKE_SOURCE_DIR}/src/popupsizepolicy.cpp
    ${CMAKE_SOURCE_DIR}/src/popupsizepolicy.h
)
target_link_libraries(test_popup_size_policy PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_popup_size_policy COMMAND test_popup_size_policy)

# DiscoverBackends — Plasma-free string/filesystem mapping (QtCore only).
add_executable(test_discoverbackends
    test_discoverbackends.cpp
    ${CMAKE_SOURCE_DIR}/src/discoverbackends.cpp
    ${CMAKE_SOURCE_DIR}/src/discoverbackends.h
)
target_link_libraries(test_discoverbackends PRIVATE Qt6::Test Qt6::Core)
add_test(NAME test_discoverbackends COMMAND test_discoverbackends)

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

# --- clang-format check ---
# Mirrors the CI clang-format step so `ctest --preset ci` fails locally
# before CI does. Skipped when clang-format isn't on PATH (distro-package
# CI runners install it; user dev shells usually have it too).
find_program(CLANG_FORMAT_EXECUTABLE NAMES clang-format)
if(CLANG_FORMAT_EXECUTABLE)
    add_test(
        NAME format_check
        COMMAND bash -c
            "cd '${CMAKE_SOURCE_DIR}' && git ls-files 'src/*.cpp' 'src/*.h' \
             | xargs '${CLANG_FORMAT_EXECUTABLE}' --dry-run -Werror"
    )
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
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/WheelGraceGate.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/WheelGraceGate.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/HoverGate.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/HoverGate.qml
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/controllers/HoverActivation.qml
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/HoverActivation.qml
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
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/launchcounts.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/launchcounts.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/constants.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/constants.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/gridmetrics.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/gridmetrics.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/gridnav.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/gridnav.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/prefixmodes.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/prefixmodes.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/themecolors.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/themecolors.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/categoryscroll.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/categoryscroll.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/categorybardisplay.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/categorybardisplay.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/scale.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/scale.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/panelgeometry.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/panelgeometry.js
        COPYONLY
    )
    # panelgeometry.js imports "devicepixels.js"; stage it beside it so the import
    # resolves under tests/qml/.
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/devicepixels.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/devicepixels.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/categoryflatten.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/categoryflatten.js
        COPYONLY
    )
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/sysinfoformat.js
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/sysinfoformat.js
        COPYONLY
    )
    # PrefixDetector imports "../js/prefixmodes.js"; stage it at the matching
    # relative path (tests/js/) so the copied component resolves it.
    configure_file(
        ${CMAKE_SOURCE_DIR}/package/contents/ui/js/prefixmodes.js
        ${CMAKE_CURRENT_SOURCE_DIR}/js/prefixmodes.js
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
