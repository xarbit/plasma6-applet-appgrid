/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents

import "../widgets"

ScrollableColumn {
    id: infoView

    property var sharedFavoritesModel: null

    // Injected from the boundary (see inner-widget-decoupling-plan.md).
    required property var sysInfo
    required property var updateChecker
    required property bool favoritesPortedToKAstats
    required property list<string> favoriteApps
    // markUnported() clears the KAStats migration flag at the boundary.
    required property var markUnported

    readonly property bool _migrated: infoView.favoritesPortedToKAstats
    readonly property int _kastatsCount: sharedFavoritesModel ? sharedFavoritesModel.count : 0
    readonly property int _localCount: infoView.favoriteApps.length

    PlasmaComponents.Label {
        text: i18nd("dev.xarbit.appgrid", "System Information")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
    }

    Repeater {
        model: [
            { label: "AppGrid",  value: infoView.sysInfo.appgridVersion || "", checkUpdates: true },
            { label: "Install",  value: infoView.sysInfo.installType || "" },
            { label: "Variant",  value: infoView.sysInfo.variant || "" },
            { label: "Session",  value: infoView.sysInfo.sessionType || "" },
            { label: "Plasma",   value: infoView.sysInfo.plasmaVersion || "" },
            { label: "KF",       value: infoView.sysInfo.kfVersion || "" },
            { label: "Qt",       value: infoView.sysInfo.qtVersion || "" },
            { label: "OS",       value: infoView.sysInfo.os || "" },
            { label: "Screens",  value: infoView.sysInfo.screens || "" }
        ]

        delegate: Item {
            Layout.fillWidth: true
            implicitHeight: infoRow.implicitHeight + Kirigami.Units.largeSpacing * 2

            RowLayout {
                id: infoRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: Kirigami.Units.largeSpacing

                PlasmaComponents.Label {
                    text: modelData.label
                    font.bold: true
                    opacity: 0.6
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                }

                PlasmaComponents.Label {
                    text: modelData.value
                    font.family: "monospace"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                PlasmaComponents.ToolButton {
                    visible: modelData.checkUpdates === true
                             && !!infoView.updateChecker
                    icon.name: checkUpdatesBusy.running ? "view-refresh" : "system-software-update"
                    text: infoView.updateChecker && infoView.updateChecker.hasUpdate === true
                          ? i18nd("dev.xarbit.appgrid", "Update %1 available",
                                  infoView.updateChecker.latestVersion)
                          : i18nd("dev.xarbit.appgrid", "Check for updates")
                    display: PlasmaComponents.AbstractButton.TextBesideIcon
                    PlasmaComponents.ToolTip.text: infoView.updateChecker && infoView.updateChecker.hasUpdate === true
                        ? i18nd("dev.xarbit.appgrid",
                                "Click to open release notes for %1",
                                infoView.updateChecker.latestVersion)
                        : i18nd("dev.xarbit.appgrid",
                                "Force an immediate check against the AppGrid website (bypasses the 24h schedule).")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                    onClicked: {
                        if (!infoView.updateChecker) return
                        if (infoView.updateChecker.hasUpdate === true) {
                            infoView.updateChecker.openReleasePage()
                        } else {
                            infoView.updateChecker.checkNow()
                            checkUpdatesBusy.restart()
                        }
                    }
                    Timer {
                        id: checkUpdatesBusy
                        interval: 2000
                    }
                }
            }

            KSvg.SvgItem {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                imagePath: "widgets/line"
                elementId: "horizontal-line"
                implicitHeight: 0.5
            }
        }
    }

    // -- Favorites backend status --
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.Label {
            text: i18nd("dev.xarbit.appgrid", "Favorites")
            font.bold: true
            opacity: 0.6
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            font.family: "monospace"
            text: infoView._migrated
                ? i18nd("dev.xarbit.appgrid", "KAStats (%1 entries; legacy backup: %2)",
                        infoView._kastatsCount, infoView._localCount)
                : i18nd("dev.xarbit.appgrid", "Not migrated (legacy: %1 entries)",
                        infoView._localCount)
            elide: Text.ElideRight
        }

        PlasmaComponents.ToolButton {
            visible: infoView._migrated
            icon.name: "edit-undo"
            text: i18nd("dev.xarbit.appgrid", "Re-run migration")
            PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Clears the migration flag. On next open, AppGrid recomputes the favorites list as the union of the legacy backup and current KAStats entries. Nothing is lost; missing legacy items are re-added.")
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            onClicked: {
                infoView.markUnported()
                migrateHintTimer.start()
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: migrateHintTimer.running
        text: i18nd("dev.xarbit.appgrid",
            "Migration flag cleared. Reopen AppGrid to re-run the port.")
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        horizontalAlignment: Text.AlignRight
    }

    Timer {
        id: migrateHintTimer
        interval: 5000
    }

    PlasmaComponents.Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.largeSpacing
        icon.name: copyTimer.running ? "dialog-ok-apply" : "edit-copy"
        text: copyTimer.running
            ? i18nd("dev.xarbit.appgrid", "Copied!")
            : i18nd("dev.xarbit.appgrid", "Copy to Clipboard")
        onClicked: {
            var info = infoView.sysInfo
            var lines = [
                "AppGrid: " + (info.appgridVersion || ""),
                "Install: " + (info.installType || ""),
                "Variant: " + (info.variant || ""),
                "Session: " + (info.sessionType || ""),
                "Plasma: " + (info.plasmaVersion || ""),
                "KF: " + (info.kfVersion || ""),
                "Qt: " + (info.qtVersion || ""),
                "OS: " + (info.os || ""),
                "Screens: " + (info.screens || ""),
                "Favorites: " + (infoView._migrated
                    ? "KAStats (" + infoView._kastatsCount + "; backup " + infoView._localCount + ")"
                    : "not migrated (" + infoView._localCount + ")")
            ]
            infoClipboard.text = lines.join("\n")
            infoClipboard.selectAll()
            infoClipboard.copy()
            copyTimer.start()
        }

        Timer {
            id: copyTimer
            interval: 2000
        }

        TextEdit {
            id: infoClipboard
            visible: false
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18nd("dev.xarbit.appgrid", "Include this info when reporting issues on GitHub")
        font: Kirigami.Theme.smallFont
        opacity: 0.35
        horizontalAlignment: Text.AlignHCenter
    }
}
