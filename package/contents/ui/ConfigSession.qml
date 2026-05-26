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

    property var cfg_powerButtonOrder: Plasmoid.configuration.powerButtonOrder
    property var cfg_powerButtonsHidden: Plasmoid.configuration.powerButtonsHidden
    property alias cfg_showActionLabels: showActionLabels.checked

    function _isHidden(id) {
        return (page.cfg_powerButtonsHidden || []).indexOf(id) >= 0
    }
    function _setHidden(id, hide) {
        var h = (page.cfg_powerButtonsHidden || []).slice()
        var i = h.indexOf(id)
        if (hide && i < 0) h.push(id)
        else if (!hide && i >= 0) h.splice(i, 1)
        page.cfg_powerButtonsHidden = h
    }

    Kirigami.FormLayout {
        PowerButtonsConfig {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Top-level buttons:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            buttonOrder: page.cfg_powerButtonOrder
            hiddenButtons: page.cfg_powerButtonsHidden
            onEdited: (newOrder, newHidden) => {
                page.cfg_powerButtonOrder = newOrder
                page.cfg_powerButtonsHidden = newHidden
            }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Session menu items:")
            text: i18nd("dev.xarbit.appgrid", "Lock")
            checked: !page._isHidden("lock")
            onToggled: page._setHidden("lock", !checked)
        }
        QQC2.CheckBox {
            text: i18nd("dev.xarbit.appgrid", "Log Out")
            checked: !page._isHidden("logout")
            onToggled: page._setHidden("logout", !checked)
        }
        QQC2.CheckBox {
            text: i18nd("dev.xarbit.appgrid", "Switch User")
            checked: !page._isHidden("switchuser")
            onToggled: page._setHidden("switchuser", !checked)
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showActionLabels
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Display:")
            text: i18nd("dev.xarbit.appgrid", "Show labels on power/session buttons")
        }
    }
}
