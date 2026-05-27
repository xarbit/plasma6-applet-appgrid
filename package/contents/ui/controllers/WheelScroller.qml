/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Mouse-wheel scrolling for a Flickable. Kirigami.WheelHandler event-
    filters the target, so it overrides a bare Flickable's slow built-in
    wheel handling; touchpad scrolling stays smooth. Set `target` to the
    Flickable. Uses Kirigami's default step (20 × the desktop's
    wheelScrollLines); set verticalStepSize here to override.
*/

import org.kde.kirigami as Kirigami

Kirigami.WheelHandler {
}
