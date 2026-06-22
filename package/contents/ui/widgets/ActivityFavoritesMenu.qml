/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The "Show in Favorites" submenu, mirroring Kicker: "On All Activities" plus a
    checkable entry per activity. Works on any app — picking an activity on a
    non-favourite favourites it there. Reports the chosen activity-id set; the
    caller pushes it to the model. Only attached when more than one activity
    exists (otherwise a favourite is simply on or off).

    The activity items are built once (the list is stable); their checked state is
    a live binding, so reopening the menu for a different app updates the marks
    without rebuilding the menu (rebuilding it on every open corrupted it).
*/

import QtQuick

import org.kde.plasma.components as PlasmaComponents

AppGridMenu {
    id: root

    title: i18nd("dev.xarbit.appgrid", "Show in Favorites")

    // [{id, name}] of the running activities, the activity ids this app's
    // favourite is pinned to (empty = all activities), and whether it's a
    // favourite at all (so a non-favourite shows nothing checked).
    property var activities: []
    property var linkedActivities: []
    property bool isFavorite: false

    readonly property bool _isGlobal: isFavorite && linkedActivities.length === 0

    // The new desired activity-id set; an empty list means "all activities".
    signal chosen(var activityIds)

    PlasmaComponents.MenuItem {
        text: i18nd("dev.xarbit.appgrid", "On All Activities")
        checkable: true
        checked: root._isGlobal
        onClicked: root.chosen([])
    }

    PlasmaComponents.MenuSeparator {}

    Instantiator {
        model: root.activities
        delegate: PlasmaComponents.MenuItem {
            required property int index
            property string activityId: ""
            checkable: true
            // Live: re-evaluates when linkedActivities changes for the next app,
            // so the menu need not be rebuilt per open.
            checked: activityId.length > 0 && !root._isGlobal
                     && root.linkedActivities.indexOf(activityId) >= 0
            // An Instantiator item loses its modelData when insertItem reparents
            // it, so read the activity by index and capture once (as FolderTargetMenu).
            Component.onCompleted: {
                const a = root._activityAt(index)
                if (a) {
                    activityId = a.id || ""
                    text = a.name || i18nd("dev.xarbit.appgrid", "Activity")
                }
            }
            onClicked: root._toggle(activityId)
        }
        onObjectAdded: (idx, obj) => root.insertItem(idx, obj)
        onObjectRemoved: (idx, obj) => root.removeItem(obj)
    }

    function _activityAt(index) {
        return (index >= 0 && index < root.activities.length) ? root.activities[index] : null
    }

    // Toggle one activity in the set; from "all" (or a non-favourite), the first
    // pick narrows to just that activity, and clearing the last one falls back to
    // all activities.
    function _toggle(activityId) {
        let set = root._isGlobal ? [] : root.linkedActivities.slice()
        const i = set.indexOf(activityId)
        if (i >= 0) {
            set.splice(i, 1)
        } else {
            set.push(activityId)
        }
        root.chosen(set)
    }
}
