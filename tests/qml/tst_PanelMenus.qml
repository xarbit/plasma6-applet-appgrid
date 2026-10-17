/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for PanelMenus.qml: it loads from plain stubs, and a search
    result's menu asks the runner about the runner's own row, not the
    unified search row.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/views"

TestCase {
    id: testCase
    name: "PanelMenus"
    width: 400
    height: 400
    when: windowShown

    property var favoriteIdRows: []
    property var actionRows: []

    QtObject {
        id: cfgStub
        property bool favoriteFoldersEnabled: false
        property bool enableActivities: false
    }

    QtObject {
        id: searchStub
        function get(index) { return index === 7 ? ({ sourceIndex: 2 }) : null }
        function runnerActions(index) { testCase.actionRows.push(index); return [] }
    }

    Component {
        id: menusComponent
        PanelMenus {
            cfg: cfgStub
            searchModel: searchStub
            launcherActions: ({
                pinToTaskManager: df => {}, addToDesktop: df => {},
                canPinToTaskManager: () => false, canAddToDesktop: () => false,
                editMenuItem: path => {}
            })
            plasmoidBridge: ({
                menuTreeModel: null,
                launchService: ({ appActions: sid => [], launchAction: (sid, name) => {} }),
                systemActions: ({ canManageInDiscover: sid => false, openInDiscover: sid => {} }),
                runner: ({
                    favoriteId: function(row) { testCase.favoriteIdRows.push(row); return "" },
                    runAction: (row, action) => false
                })
            })
        }
    }

    function test_runnerResultUsesTheRunnerRow() {
        favoriteIdRows = []
        actionRows = []
        var menus = createTemporaryObject(menusComponent, testCase)
        verify(menus)
        menus.showForRunnerResult(7)
        compare(favoriteIdRows.join(","), "2", "the runner's row")
        compare(actionRows.join(","), "7", "actions by the unified row")
        menus.showForRunnerResult(3)
        compare(favoriteIdRows.length, 1, "no menu for a row that isn't there")
        menus.close()
    }
}
