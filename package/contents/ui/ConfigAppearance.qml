/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    readonly property bool isPanel: Plasmoid.pluginName === "dev.xarbit.appgrid.panel"

    property alias cfg_showDividers: showDividers.checked
    property alias cfg_showScrollbars: showScrollbars.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showNewAppBadge: showNewAppBadge.checked
    property alias cfg_iconShadow: iconShadow.checked
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_enableBlur: enableBlur.checked
    property alias cfg_dimBackground: dimBackground.checked
    property alias cfg_overrideRadius: overrideRadius.checked
    property alias cfg_cornerRadius: cornerRadius.value

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showDividers
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Grid:")
            text: i18nd("dev.xarbit.appgrid", "Show divider lines")
        }
        QQC2.CheckBox {
            id: showScrollbars
            text: i18nd("dev.xarbit.appgrid", "Show scrollbars")
        }
        QQC2.CheckBox {
            id: showTooltips
            text: i18nd("dev.xarbit.appgrid", "Show tooltips on hover")
        }
        QQC2.CheckBox {
            id: showNewAppBadge
            text: i18nd("dev.xarbit.appgrid", "Show new app badge")
        }
        QQC2.CheckBox {
            id: iconShadow
            text: i18nd("dev.xarbit.appgrid", "Drop shadow behind app icons")
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.Slider {
            id: backgroundOpacity
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Background opacity:")
            from: 10; to: 100; stepSize: 5
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.CheckBox {
            id: enableBlur
            visible: !page.isPanel
            text: i18nd("dev.xarbit.appgrid", "Enable background blur")
        }
        QQC2.CheckBox {
            id: dimBackground
            visible: !page.isPanel
            text: i18nd("dev.xarbit.appgrid", "Dim background behind launcher")
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: overrideRadius
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Corner radius:")
            text: i18nd("dev.xarbit.appgrid", "Use custom corner radius")
        }
        QQC2.SpinBox {
            id: cornerRadius
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Radius (px):")
            enabled: overrideRadius.checked
            from: 0; to: 60
        }
    }
}
