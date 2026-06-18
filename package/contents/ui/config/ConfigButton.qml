/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Center variant's only Plasma applet config page: the panel button's icon and
    text label, plus a button to open the launcher's own settings window (the
    daemon). Every other setting moved to that window (grid, appearance, search,
    header actions, hidden apps), so the applet config carries just the button
    appearance here plus Plasma's own Keyboard Shortcuts and About pages.

    The Icon: / Text label: controls are placed as direct children of this one
    FormLayout (not a nested sub-form) so they share its label column and wide/
    wrap mode with the Launcher: row below — see #191.
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

        IconPickerButton {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon:")
            configuration: buffer
            location: Plasmoid.location
            defaultIcon: Const.PLUGIN_ID_CENTER
        }

        LauncherLabelField {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Text label:")
            configuration: buffer
            formFactor: Plasmoid.formFactor
        }

        Item { Kirigami.FormData.isSection: true }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: true
            type: Kirigami.MessageType.Information
            text: i18nd("dev.xarbit.appgrid",
                "The AppGrid launcher center variant now runs as its own application (like KRunner), so it can use the desktop's window effects and theming. Because of that, its settings — grid layout, appearance, search and hidden applications — have moved into the launcher's own window.\n\nThis page configures only the panel button shown here: its icon and text label. To change the launcher's settings, open it with the button below, or use the Settings action in the launcher's header.")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Launcher:")
            text: i18ndc("dev.xarbit.appgrid", "@action:button open the standalone launcher settings window", "Configure Launcher…")
            icon.name: "configure"
            onClicked: Plasmoid.configureStandaloneWindow()
        }
    }
}
