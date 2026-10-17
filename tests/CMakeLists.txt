# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Test)
include(ECMAddTests)

# StubAppModel, the fake app list the model tests filter, sort and group.
add_library(appgrid_teststubs STATIC stubappmodel.h)
target_link_libraries(appgrid_teststubs PUBLIC appgrid_core)

# Each test is one source file linked against the launcher core.
ecm_add_tests(
    test_appactionid.cpp
    test_appfiltermodel.cpp
    test_appmodel.cpp
    test_appranking.cpp
    test_appurl.cpp
    test_appsearch.cpp
    test_appmodel_assembly.cpp
    test_appmodel_helpers.cpp
    test_category_mapping.cpp
    test_categoryqueries.cpp
    test_categoryrows.cpp
    test_configkeys.cpp
    test_discoverbackends.cpp
    test_favoriteid.cpp
    test_favoritesfolderlogic.cpp
    test_favoritesgroupedmodel.cpp
    test_filter.cpp
    test_frecency_scoring.cpp
    test_launchbookkeeping.cpp
    test_launchstatestore.cpp
    test_menutree.cpp
    test_newappstracker.cpp
    test_installsource.cpp
    test_configcleanup.cpp
    test_defaultappsresolver.cpp
    test_launchservice.cpp
    test_localsystem.cpp
    test_plasmoidclient.cpp
    test_runner_filter.cpp
    test_runnerresults.cpp
    test_search_ranking.cpp
    test_sort.cpp
    test_systemactions.cpp
    test_unified_search.cpp
    LINK_LIBRARIES appgrid_teststubs appgrid_core Qt6::Test
)
# Settings key parity reads the QML sources directly.
target_compile_definitions(test_configkeys PRIVATE APPGRID_SOURCE_DIR="${CMAKE_SOURCE_DIR}")

# The update checker is only built into universal packages.
if(APPGRID_UNIVERSAL_BUILD)
    ecm_add_test(test_updatechecker.cpp LINK_LIBRARIES appgrid_core Qt6::Test)
endif()

# PopupSizePolicy belongs to the panel applet, not the core.
ecm_add_test(test_popup_size_policy.cpp ${CMAKE_SOURCE_DIR}/src/popupsizepolicy.cpp
    TEST_NAME test_popup_size_policy
    LINK_LIBRARIES Qt6::Test Qt6::Core)
target_include_directories(test_popup_size_policy PRIVATE ${CMAKE_SOURCE_DIR}/src)

# AppGridStandalone belongs to the daemon. Its D-Bus surface is called
# through the adaptor generated from the interface XML.
set(TEST_STANDALONE_SOURCES test_standalone.cpp ${CMAKE_SOURCE_DIR}/src/standalone/appgridstandalone.cpp)
qt_add_dbus_adaptor(TEST_STANDALONE_SOURCES ${APPGRID_DBUS_STANDALONE_XML} standalone/appgridstandalone.h AppGridStandalone standaloneadaptor StandaloneAdaptor)
ecm_add_test(${TEST_STANDALONE_SOURCES}
    TEST_NAME test_standalone
    LINK_LIBRARIES appgrid_core Qt6::Test)
target_include_directories(test_standalone PRIVATE ${CMAKE_SOURCE_DIR}/src/standalone ${CMAKE_CURRENT_BINARY_DIR})

# The daemon's command line and settings autosave, also daemon-only.
ecm_add_test(test_standaloneoptions.cpp
    ${CMAKE_SOURCE_DIR}/src/standalone/standaloneoptions.cpp
    ${CMAKE_SOURCE_DIR}/src/standalone/configautosave.cpp
    TEST_NAME test_standaloneoptions
    LINK_LIBRARIES appgrid_core Qt6::Test)
target_include_directories(test_standaloneoptions PRIVATE ${CMAKE_SOURCE_DIR}/src/standalone)

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
    # The tests load the components and JS libraries straight from package/
    # by relative path, so they always run against the shipped files.
    add_executable(tst_qml qml/main.cpp)
    target_link_libraries(tst_qml PRIVATE appgrid_core Qt6::QuickTest Qt6::Quick Qt6::Qml Qt6::Core)
    target_compile_definitions(tst_qml PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
    add_test(NAME tst_qml COMMAND tst_qml)
else()
    message(STATUS "Qt6QuickTest not found — skipping QML tests")
endif()
