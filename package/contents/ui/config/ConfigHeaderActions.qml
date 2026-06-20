/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigHeaderActionsContent. A `cfg_<key>`
    property per setting drives Plasma's dirty-tracking and the KConfigXT flush
    (#191); the shared Content writes to the buffer QtObject so edits stay staged
    until Apply/OK.
*/

import QtQuick

import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property alias cfg_headerActions: buffer.headerActions
    property alias cfg_customHeaderActions: buffer.customHeaderActions
    property alias cfg_menuButtonIcon: buffer.menuButtonIcon
    property alias cfg_showActionLabels: buffer.showActionLabels
    property alias cfg_hideMenuButtonLabel: buffer.hideMenuButtonLabel

    QtObject {
        id: buffer
        property var headerActions
        property var customHeaderActions
        property string menuButtonIcon
        property bool showActionLabels
        property bool hideMenuButtonLabel
    }

    ConfigHeaderActionsContent {
        width: page.width
        configuration: buffer
        isUniversalBuild: Plasmoid.isUniversalBuild
    }
}
