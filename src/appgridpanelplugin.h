/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "appgridplugin.h"

class AppGridPanelPlugin : public AppGridPlugin
{
    Q_OBJECT

public:
    AppGridPanelPlugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    ~AppGridPanelPlugin() override;

    /**
     * Mirror Plasma's per-instance popupWidth/popupHeight values into the
     * applet's globalConfig (keyed by plugin id, persists across instance
     * replacement) and stamp the slot's `popupSizeOwner` tag with our id
     * + the current size. Called from QML on popup close AND from the
     * destructor so the user's chosen size survives an alternatives-
     * switch from Kicker/Kickoff. See #87.
     */
    Q_INVOKABLE void persistPopupSize();

private:
    /**
     * Decide whether the per-instance popupWidth/popupHeight in our slot
     * config are "ours" or were left behind by another launcher we just
     * replaced. The `popupSizeOwner` tag carries our id AND the size we
     * wrote — checking both catches the case where another launcher
     * mutated popupWidth/Height without touching the tag. On stranger,
     * restore from globalConfig (the user's last AppGrid size) or clear
     * the keys so AppletPopup falls back to GridPanel's implicit size.
     */
    void restorePopupSizeIfStranger();
};
