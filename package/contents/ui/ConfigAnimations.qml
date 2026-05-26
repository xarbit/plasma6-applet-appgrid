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

    property alias cfg_openAnimation: openAnimation.currentIndex
    property alias cfg_hoverAnimation: hoverAnimation.currentIndex
    property alias cfg_shakeOnOpen: shakeOnOpen.checked

    Kirigami.FormLayout {
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

        Item {
            visible: !page.isPanel
            Kirigami.FormData.isSection: true
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
