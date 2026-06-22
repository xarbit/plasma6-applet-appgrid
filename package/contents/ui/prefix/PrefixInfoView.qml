/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../widgets"
import "../js/sysinfoformat.js" as SysInfoFormat

ScrollableColumn {
    id: infoView

    // Only flick when the content overflows; otherwise the Flickable steals the
    // press-drag and the SelectableLabel values can't be selected.
    interactive: contentHeight > height

    // Injected from the boundary (see inner-widget-decoupling-plan.md).
    // A provider function, called once when this view is built (it's only
    // instantiated on the i: info prefix), so the underlying /proc + os-release
    // reads stay off the launcher's open path (#200).
    required property var sysInfoProvider
    readonly property var sysInfo: infoView.sysInfoProvider ? infoView.sysInfoProvider() : ({})
    required property var updateChecker

    PlasmaComponents.Label {
        text: i18nd("dev.xarbit.appgrid", "System Information")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
    }

    Repeater {
        model: [
            { label: "AppGrid",  value: infoView.sysInfo.appgridVersion || "", checkUpdates: true },
            { label: i18nd("dev.xarbit.appgrid", "Install"),  value: infoView.sysInfo.installType || "" },
            { label: i18nd("dev.xarbit.appgrid", "Variant"),  value: infoView.sysInfo.variant || "" },
            { label: i18nd("dev.xarbit.appgrid", "Session"),  value: infoView.sysInfo.sessionType || "" },
            { label: "Plasma",   value: infoView.sysInfo.plasmaVersion || "" },
            { label: "KF",       value: infoView.sysInfo.kfVersion || "" },
            { label: "Qt",       value: infoView.sysInfo.qtVersion || "" },
            { label: "OS",       value: infoView.sysInfo.os || "" },
            { label: i18nd("dev.xarbit.appgrid", "Screens"),  value: infoView.sysInfo.screens || "" }
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

                // Selectable so a single value can be copied on its own; the
                // Copy button below still grabs the whole block.
                Kirigami.SelectableLabel {
                    text: modelData.value
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    Layout.fillWidth: true
                    wrapMode: Text.NoWrap
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

            HorizontalDivider {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
            }
        }
    }

    PlasmaComponents.Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.largeSpacing
        icon.name: copyTimer.running ? "dialog-ok-apply" : "edit-copy"
        text: copyTimer.running
            ? i18nd("dev.xarbit.appgrid", "Copied!")
            : i18nd("dev.xarbit.appgrid", "Copy to Clipboard")
        onClicked: {
            infoClipboard.text = SysInfoFormat.clipboardText(infoView.sysInfo)
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
