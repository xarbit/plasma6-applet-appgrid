/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The launcher button's text-label field as a SINGLE form control, placed
    directly in the host's Kirigami.FormLayout (the host sets FormData.label) so
    it aligns with every other row (#191). Disabled on a vertical panel, where
    the button shows no text.

    The value binding depends on `revision` so a host can force a re-read after a
    revert / load-defaults.
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

Kirigami.ActionTextField {
    id: field

    property var configuration
    property int formFactor: 0          // PlasmaCore.Types.FormFactor
    property int revision: 0

    Layout.fillWidth: true
    Layout.minimumWidth: Kirigami.Units.gridUnit * 14
    placeholderText: i18nd("dev.xarbit.appgrid", "Type here to add a text label")
    text: { void field.revision; return field.configuration.menuLabel }
    onTextChanged: field.configuration.menuLabel = text
    enabled: field.formFactor !== PlasmaCore.Types.Vertical
    rightActions: Kirigami.Action {
        icon.name: "edit-clear"
        visible: field.text.length > 0
        onTriggered: field.configuration.menuLabel = ""
    }
}
