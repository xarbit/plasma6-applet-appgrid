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

    property alias cfg_searchAll: searchAll.checked
    property alias cfg_useExtraRunners: useExtraRunners.checked

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: searchAll
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Search:")
            text: i18nd("dev.xarbit.appgrid", "Search all apps regardless of active tab")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: useExtraRunners
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Plugins:")
            text: i18nd("dev.xarbit.appgrid", "Use KDE search plugins (KRunner)")
            QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Includes the calculator, unit conversion, file search, bookmarks, web shortcuts and other KRunner plugins. Use \"Configure Search Plugins\" to choose which are active.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        QQC2.Button {
            text: i18nd("dev.xarbit.appgrid", "Configure Search Plugins…")
            icon.name: "settings-configure"
            enabled: useExtraRunners.checked
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_plasmasearch")
        }
    }
}
