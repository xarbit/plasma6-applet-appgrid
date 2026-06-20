/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A framed icon preview that opens the system icon browser on click and reports
    the chosen icon name. Shared by the custom-header-action editor and the
    header menu-button icon setting so the picker lives in one place.

    Holds no state itself: the host binds `iconName` and writes back in `picked`.
    `fallbackIcon` is shown (and named in the tooltip) when iconName is empty.
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.iconthemes as KIconThemes
import org.kde.kirigami as Kirigami

QQC2.Button {
    id: root

    property string iconName: ""
    property string fallbackIcon: ""
    // Emitted with the picked freedesktop icon name.
    signal picked(string name)

    // Framed (not flat) so it reads as a clickable control even when the icon is
    // something minimal like the overflow dots (#190).
    implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
    implicitHeight: implicitWidth
    onClicked: iconDialog.open()

    QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Choose icon (%1)", root.iconName || root.fallbackIcon)
    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.medium
        height: width
        source: root.iconName || root.fallbackIcon
    }

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: name => root.picked(name)
    }
}
