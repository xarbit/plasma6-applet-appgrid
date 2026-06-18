/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigAppearanceContent. A `cfg_<key>`
    property per setting drives Plasma's dirty-tracking and the KConfigXT flush
    (#191); the shared Content writes to the buffer QtObject (property names match
    the keys) so edits stay staged until Apply/OK.

    showCategoryBar is owned by the General page — this page only READS it to gate
    a dependent option, so it is bound live (no cfg_ here) to avoid two pages
    declaring the same cfg_ key and clobbering each other on Apply.
*/

import QtQuick

import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

import "../js/constants.js" as Const

KCM.SimpleKCM {
    id: page

    property alias cfg_hideGridWhenEmpty: buffer.hideGridWhenEmpty
    property alias cfg_hideLabelsOnFavorites: buffer.hideLabelsOnFavorites
    property alias cfg_hoverAnimation: buffer.hoverAnimation
    property alias cfg_hoverHighlight: buffer.hoverHighlight
    property alias cfg_iconShadow: buffer.iconShadow
    property alias cfg_independentTextSize: buffer.independentTextSize
    property alias cfg_reduceGridSpacing: buffer.reduceGridSpacing
    property alias cfg_shakeOnOpen: buffer.shakeOnOpen
    property alias cfg_showDividers: buffer.showDividers
    property alias cfg_showNewAppBadge: buffer.showNewAppBadge
    property alias cfg_showScrollbars: buffer.showScrollbars
    property alias cfg_showTooltips: buffer.showTooltips

    QtObject {
        id: buffer
        property bool hideGridWhenEmpty
        property bool hideLabelsOnFavorites
        property int hoverAnimation
        property bool hoverHighlight
        property bool iconShadow
        property bool independentTextSize
        property bool reduceGridSpacing
        property bool shakeOnOpen
        property bool showDividers
        property bool showNewAppBadge
        property bool showScrollbars
        property bool showTooltips
        // Read-only gate value, owned + saved by the General page.
        readonly property bool showCategoryBar: Plasmoid.configuration.showCategoryBar
    }

    ConfigAppearanceContent {
        configuration: buffer
        isPanel: Plasmoid.pluginName === Const.PLUGIN_ID_PANEL
    }
}
