/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Centre-variant panel icon. Resolves configuration through ConfigCache
    and warms the launcher window on hover; the visual structure lives in
    the shared CompactRepresentationBase.
*/

import "widgets"
import "controllers"

CompactRepresentationBase {
    id: root

    required property var configuration

    ConfigCache { id: cfg; source: root.configuration }

    preloadOnHover: true

    iconSource: cfg.icon
    customButtonImageEnabled: cfg.useCustomButtonImage
    customButtonImageSource: cfg.customButtonImage.toString()
    menuLabel: cfg.menuLabel
}
