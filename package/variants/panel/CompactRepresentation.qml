/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Panel-variant icon. Reads the plasmoid configuration directly (the
    native popup needs no window preload); the visual structure lives in
    the shared CompactRepresentationBase.
*/

import "widgets"

CompactRepresentationBase {
    id: root

    required property var configuration

    iconSource: root.configuration.icon !== undefined ? root.configuration.icon : ""
    customButtonImageEnabled: root.configuration.useCustomButtonImage === true
    customButtonImageSource: root.configuration.customButtonImage || ""
    menuLabel: root.configuration.menuLabel || ""
}
