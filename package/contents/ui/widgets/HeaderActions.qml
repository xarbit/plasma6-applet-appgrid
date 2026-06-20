/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The right-hand side of the panel header: the power/header-action strip that
    animates aside on search to reveal the current result's icon, plus the
    standalone daemon's settings gear. Pulled out of GridPanel so the hub keeps
    only the search field and the keyboard routing. The search field reads
    `animRunning` (hide its clear button mid-animation) and `actionsImplicitHeight`
    (pin the header row height so it doesn't shrink when the strip hides).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    // Panel state.
    property bool isSearching: false
    property bool showSearchResults: false
    property string currentResultIcon: ""
    property real densityScale: 1.0
    // Config-driven appearance + the action data.
    property bool showActionLabels: false
    property bool hideMenuButtonLabel: false
    property var headerActions: []
    // Custom user actions (#196): raw config list + a command runner + shell.
    property var customHeaderActions: []
    property var commandRunner: null
    property string terminalShell: ""
    property string menuButtonIcon: ""
    property bool iconShadow: false
    property var updateChecker: null
    property var sessionActions: null
    // Whether the in-strip "settings" header action can open settings (both
    // shipped variants can; a host without a settings surface sets it false).
    property bool canConfigure: true

    signal actionTriggered()
    // Emitted by the "settings" header action; the host opens its settings.
    signal configureRequested()

    // Mid-animation flag (search field hides its X while the slot resizes) and
    // the strip's intrinsic height (valid even while the strip is hidden).
    readonly property alias animRunning: headerSlotAnim.running
    readonly property alias actionsImplicitHeight: headerActionStrip.implicitHeight

    function closeMenus() { headerActionStrip.closeMenus() }

    spacing: Kirigami.Units.largeSpacing

    // Right-side header slot. Animates its allocated width between the strip's
    // natural width (idle) and the search-result icon's width (searching).
    // Behavior on Layout.preferredWidth turns what would be a hard reflow jump on
    // the first keystroke into a smooth shrink, while leaving zero dead space at
    // the steady state.
    Item {
        id: headerSlot
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: Math.max(headerActionStrip.implicitHeight,
                                         Kirigami.Units.iconSizes.medium)
        readonly property real _iconReservation: Kirigami.Units.iconSizes.medium * root.densityScale
        Layout.preferredWidth: root.isSearching
            ? (root.showSearchResults && root.currentResultIcon !== ""
                 ? _iconReservation : 0)
            : headerActionStrip.implicitWidth
        Behavior on Layout.preferredWidth {
            NumberAnimation {
                id: headerSlotAnim
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.OutQuart
            }
        }
        clip: true

        HeaderActionStrip {
            id: headerActionStrip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // `visible: false` (not opacity:0) so the buttons stop hit-testing —
            // hovering the empty slot mid-animation otherwise pops their tooltips.
            visible: !root.isSearching
            showActionLabels: root.showActionLabels
            hideMenuButtonLabel: root.hideMenuButtonLabel
            headerActions: root.headerActions
            customHeaderActions: root.customHeaderActions
            commandRunner: root.commandRunner
            terminalShell: root.terminalShell
            menuButtonIcon: root.menuButtonIcon
            updateChecker: root.updateChecker
            sessionActions: root.sessionActions
            canConfigure: root.canConfigure
            onActionTriggered: root.actionTriggered()
            onConfigureRequested: root.configureRequested()
        }

        // Current search-result icon, shown in place of the power buttons while
        // searching. Fixed size — a fillHeight icon rounds to different standard
        // sizes as the header reflows, making it visibly jump.
        ShadowedIcon {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: headerSlot._iconReservation
            height: headerSlot._iconReservation
            visible: root.showSearchResults && root.currentResultIcon !== ""
            source: root.currentResultIcon
            shadowEnabled: root.iconShadow
        }
    }
}
