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

import "../js/constants.js" as Const

KCM.SimpleKCM {
    id: page

    readonly property bool isPanel: Plasmoid.pluginName === Const.PLUGIN_ID_PANEL

    property alias cfg_showDividers: showDividers.checked
    property alias cfg_showScrollbars: showScrollbars.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showNewAppBadge: showNewAppBadge.checked
    property alias cfg_iconShadow: iconShadow.checked
    property alias cfg_hoverHighlight: hoverHighlight.checked
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_enableBlur: enableBlur.checked
    property alias cfg_dimBackground: dimBackground.checked
    property alias cfg_overrideRadius: overrideRadius.checked
    property alias cfg_cornerRadius: cornerRadius.value
    property alias cfg_useThemeBackground: useThemeBackground.checked
    property alias cfg_hideGridWhenEmpty: hideGridWhenEmpty.checked
    property alias cfg_openAnimation: openAnimation.currentIndex
    property alias cfg_hoverAnimation: hoverAnimation.currentIndex
    property alias cfg_shakeOnOpen: shakeOnOpen.checked

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
            text: i18nd("dev.xarbit.appgrid", "Show tooltips on app icons")
            QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
                "Hover-tooltips on grid + recents + by-category app icons. Other tooltips (header actions, More options, settings) are always shown — Qt/KDE has no system-wide tooltip toggle to follow.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.CheckBox {
            id: showNewAppBadge
            text: i18nd("dev.xarbit.appgrid", "Show new app badge")
        }
        QQC2.CheckBox {
            id: iconShadow
            text: i18nd("dev.xarbit.appgrid", "Drop shadow behind app icons")
        }
        QQC2.CheckBox {
            id: hoverHighlight
            text: i18nd("dev.xarbit.appgrid", "Highlight icons on hover")
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: useThemeBackground
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Chrome:")
            text: i18nd("dev.xarbit.appgrid", "Use Plasma theme background")
            QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
                "Draw the panel using the active Plasma theme's dialog background — matches Kickoff and the panel-popup variant exactly. The theme owns the chrome and Plasma's defaults take over: full opacity, blur and contrast forced on, no wallpaper dim, corner radius from the theme. The custom controls for those are disabled while this is on.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.Slider {
            id: backgroundOpacity
            visible: !page.isPanel
            enabled: !useThemeBackground.checked
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Background:")
            from: 10; to: 100; stepSize: 5
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 14
            QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Panel opacity")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.CheckBox {
            id: enableBlur
            visible: !page.isPanel
            enabled: !useThemeBackground.checked
            text: i18nd("dev.xarbit.appgrid", "Enable blur and contrast")
        }
        QQC2.CheckBox {
            id: dimBackground
            visible: !page.isPanel
            enabled: !useThemeBackground.checked
            text: i18nd("dev.xarbit.appgrid", "Dim wallpaper around launcher")
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: overrideRadius
            visible: !page.isPanel
            enabled: !useThemeBackground.checked
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Corner radius:")
            text: i18nd("dev.xarbit.appgrid", "Use custom corner radius")
        }
        QQC2.SpinBox {
            id: cornerRadius
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Radius (px):")
            enabled: overrideRadius.checked && !useThemeBackground.checked
            from: 0; to: 60
        }

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: hideGridWhenEmpty
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Compact mode:")
            text: i18nd("dev.xarbit.appgrid", "Hide app grid until I start typing")
        }
        QQC2.Label {
            visible: hideGridWhenEmpty.visible
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            text: i18nd("dev.xarbit.appgrid",
                "Tip: press the Down arrow key to reveal the grid without typing.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            wrapMode: Text.WordWrap
        }

        Item { Kirigami.FormData.isSection: true }

        // -- Animations (folded in from the former Animations tab) --

        QQC2.ComboBox {
            id: openAnimation
            visible: !page.isPanel
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Open/close:")
            model: [
                i18nd("dev.xarbit.appgrid", "None"),
                i18nd("dev.xarbit.appgrid", "Fade"),
                i18nd("dev.xarbit.appgrid", "Scale"),
                i18nd("dev.xarbit.appgrid", "Pop"),
                i18nd("dev.xarbit.appgrid", "Slide Up"),
                i18nd("dev.xarbit.appgrid", "Slide Down"),
                i18nd("dev.xarbit.appgrid", "Glide"),
                i18nd("dev.xarbit.appgrid", "Buzz"),
                i18nd("dev.xarbit.appgrid", "Twist"),
                i18nd("dev.xarbit.appgrid", "Slam"),
                i18nd("dev.xarbit.appgrid", "Grow Up")
            ]
        }

        QQC2.ComboBox {
            id: hoverAnimation
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon hover:")
            model: [
                i18nd("dev.xarbit.appgrid", "None"),
                i18nd("dev.xarbit.appgrid", "Shake"),
                i18nd("dev.xarbit.appgrid", "Grow"),
                i18nd("dev.xarbit.appgrid", "Bounce"),
                i18nd("dev.xarbit.appgrid", "Spin"),
                i18nd("dev.xarbit.appgrid", "Shuffle")
            ]
        }

        QQC2.CheckBox {
            id: shakeOnOpen
            text: i18nd("dev.xarbit.appgrid", "Animate icons when the launcher opens")
            enabled: hoverAnimation.currentIndex > 0
        }
    }
}
