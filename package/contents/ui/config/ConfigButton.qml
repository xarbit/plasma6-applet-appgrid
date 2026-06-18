/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Center variant's only Plasma applet config page: the panel button's icon and
    text label, plus a button to open the launcher's own settings window (the
    daemon). Every other setting moved to that window (grid, appearance, search,
    header actions, hidden apps), so the applet config carries just the button
    appearance here plus Plasma's own Keyboard Shortcuts and About pages.

    ConfigButtonContent is itself a Kirigami.FormLayout; nested in this outer one
    it registers as a twin, so the Icon:/Text label: column aligns with the
    Launcher: row below.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../js/constants.js" as Const

KCM.SimpleKCM {
    id: page

    // Standard Plasma KCM contract: cfg_<key> per setting drives Apply/Cancel/
    // Defaults and the KConfigXT flush (#191). The shared Content writes to the
    // buffer (property names match the keys) so edits stay staged until Apply/OK.
    property alias cfg_icon: buffer.icon
    property alias cfg_customButtonImage: buffer.customButtonImage
    property alias cfg_useCustomButtonImage: buffer.useCustomButtonImage
    property alias cfg_menuLabel: buffer.menuLabel

    QtObject {
        id: buffer
        property string icon
        property url customButtonImage
        property bool useCustomButtonImage
        property string menuLabel
    }

    Kirigami.FormLayout {
        id: form

        ConfigButtonContent {
            configuration: buffer
            formFactor: Plasmoid.formFactor
            location: Plasmoid.location
            defaultIcon: Const.PLUGIN_ID_CENTER
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Button {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Launcher:")
            text: i18ndc("dev.xarbit.appgrid", "@action:button open the standalone launcher settings window", "Configure Launcher…")
            icon.name: "configure"
            onClicked: Plasmoid.configureStandaloneWindow()
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18nd("dev.xarbit.appgrid", "Grid layout, appearance, search and hidden apps are configured in the launcher's own settings window.")
        }
    }
}
