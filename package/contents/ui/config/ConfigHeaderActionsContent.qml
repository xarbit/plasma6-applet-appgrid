/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the Header Actions settings page. Hosts inject
    `configuration` (read/write) and `isUniversalBuild`, then place this Item
    inside their own page (giving it a width). The HeaderActionsConfig editor
    round-trips the "id:placement" StringList. Value bindings depend on
    `revision` so a host can force a re-read after revert / load-defaults.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Item {
    id: root

    // -- Injected context --------------------------------------------------
    property var configuration
    property bool isUniversalBuild: true
    property int revision: 0

    implicitHeight: column.implicitHeight

    // Centered, capped-width column; content inside it stays left-aligned. The
    // header-action rows are denser than a plain settings form (name + three
    // placement buttons + two reorder buttons), so this page gets a wider cap so
    // the action name keeps a readable width instead of eliding away (#191).
    ColumnLayout {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 32)
        spacing: Kirigami.Units.largeSpacing

        HeaderActionsConfig {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 22
            actions: (root.revision, root.configuration.headerActions)
            universalBuild: root.isUniversalBuild
            onEdited: newList => root.configuration.headerActions = newList
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18nd("dev.xarbit.appgrid",
                "Bar actions appear directly in the launcher header; Menu actions go behind a single ⋮ button (hidden when empty); Off hides the action.")
        }

        QQC2.CheckBox {
            id: showActionLabels
            text: i18nd("dev.xarbit.appgrid", "Show labels on header buttons")
            checked: (root.revision, root.configuration.showActionLabels)
            onToggled: root.configuration.showActionLabels = checked
        }

        QQC2.CheckBox {
            id: hideMenuButtonLabel
            enabled: showActionLabels.checked
            text: i18nd("dev.xarbit.appgrid", "Hide label on the menu button")
            checked: (root.revision, root.configuration.hideMenuButtonLabel)
            onToggled: root.configuration.hideMenuButtonLabel = checked
        }
    }
}
