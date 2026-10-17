/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The menu of a KRunner search result: favourite it when it is app-backed
    (apps, System Settings modules, #64), and its secondary actions (e.g. the
    calculator's "Copy result").
*/

import QtQuick

AppGridMenu {
    id: runnerMenu

    // The RunnerFilterModel row (the sourceIndex of a runner row from
    // UnifiedSearchModel.get) and its secondary actions.
    property int sourceIndex: -1
    property var actions: []
    // The result's "applications:<id>" favourite id, empty when it can't be
    // favourited, and whether it is one already.
    property string favoriteId: ""
    property bool isFavorite: false

    signal favoriteToggled(string favoriteId)
    signal actionTriggered(int sourceIndex, int actionIndex)

    function showFor(index, resultActions, id, favorite) {
        sourceIndex = index
        actions = resultActions || []
        favoriteId = id || ""
        isFavorite = favorite
        popup()
    }

    // The favourite row and the separator come first; the actions follow.
    readonly property int _staticItems: 2

    AppGridMenuItem {
        visible: runnerMenu.favoriteId.length > 0
        icon.name: runnerMenu.isFavorite ? "bookmark-remove" : "bookmark-new"
        text: runnerMenu.isFavorite
              ? i18nd("dev.xarbit.appgrid", "Remove from Favorites")
              : i18nd("dev.xarbit.appgrid", "Add to Favorites")
        onClicked: {
            runnerMenu.favoriteToggled(runnerMenu.favoriteId)
            runnerMenu.close()
        }
    }
    AppGridMenuSeparator {
        visible: runnerMenu.favoriteId.length > 0 && runnerMenu.actions.length > 0
    }

    Instantiator {
        model: runnerMenu.actions
        delegate: AppGridMenuItem {
            required property var modelData
            required property int index
            icon.name: modelData.icon || ""
            text: modelData.text || ""
            onClicked: {
                runnerMenu.actionTriggered(runnerMenu.sourceIndex, index)
                runnerMenu.close()
            }
        }
        onObjectAdded: (idx, obj) => runnerMenu.insertItem(runnerMenu._staticItems + idx, obj)
        onObjectRemoved: (idx, obj) => runnerMenu.removeItem(obj)
    }
}
