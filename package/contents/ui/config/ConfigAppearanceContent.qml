/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the Appearance/Animations settings page. Hosts inject
    `configuration` (read/write) and place this FormLayout inside their own
    scrollable page. Value bindings depend on `revision` so a host can force a
    re-read after revert / load-defaults.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    // -- Injected context --------------------------------------------------
    property var configuration
    property bool isPanel: false
    property int revision: 0

    QQC2.CheckBox {
        id: showDividers
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Grid:")
        text: i18nd("dev.xarbit.appgrid", "Show divider lines")
        checked: { void root.revision; return root.configuration.showDividers }
        onToggled: root.configuration.showDividers = checked
    }
    QQC2.CheckBox {
        id: showScrollbars
        text: i18nd("dev.xarbit.appgrid", "Show scrollbars")
        checked: { void root.revision; return root.configuration.showScrollbars }
        onToggled: root.configuration.showScrollbars = checked
    }
    QQC2.CheckBox {
        id: showTooltips
        text: i18nd("dev.xarbit.appgrid", "Show tooltips on app icons")
        checked: { void root.revision; return root.configuration.showTooltips }
        onToggled: root.configuration.showTooltips = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Hover-tooltips on grid + recents + by-category app icons. Other tooltips (header actions, More options, settings) are always shown — Qt/KDE has no system-wide tooltip toggle to follow.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    QQC2.CheckBox {
        id: showNewAppBadge
        text: i18nd("dev.xarbit.appgrid", "Show new app badge")
        checked: { void root.revision; return root.configuration.showNewAppBadge }
        onToggled: root.configuration.showNewAppBadge = checked
    }
    QQC2.CheckBox {
        id: iconShadow
        text: i18nd("dev.xarbit.appgrid", "Drop shadow behind app icons")
        checked: { void root.revision; return root.configuration.iconShadow }
        onToggled: root.configuration.iconShadow = checked
    }
    QQC2.CheckBox {
        id: hoverHighlight
        text: i18nd("dev.xarbit.appgrid", "Highlight icons on hover")
        checked: { void root.revision; return root.configuration.hoverHighlight }
        onToggled: root.configuration.hoverHighlight = checked
    }
    QQC2.CheckBox {
        id: independentTextSize
        text: i18nd("dev.xarbit.appgrid", "Apply Size to app icons only")
        checked: { void root.revision; return root.configuration.independentTextSize }
        onToggled: root.configuration.independentTextSize = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "By default the Size setting scales the whole panel. Check this to make Size change only the app icons, leaving labels, secondary icons, and spacing at the default — e.g. Medium icons with the default font.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    QQC2.CheckBox {
        id: reduceGridSpacing
        text: i18nd("dev.xarbit.appgrid", "Reduce grid spacing")
        checked: { void root.revision; return root.configuration.reduceGridSpacing }
        onToggled: root.configuration.reduceGridSpacing = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Pack the app grid more tightly by using a narrower cell width. Long single-word names may wrap to a second line sooner.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    QQC2.CheckBox {
        id: hideLabelsOnFavorites
        text: i18nd("dev.xarbit.appgrid", "Hide app labels on favorites tab")
        enabled: { void root.revision; return root.configuration.showCategoryBar }
        checked: { void root.revision; return root.configuration.hideLabelsOnFavorites }
        onToggled: root.configuration.hideLabelsOnFavorites = checked
    }
    QQC2.CheckBox {
        id: favoriteFoldersEnabled
        text: i18nd("dev.xarbit.appgrid", "Group favorites into folders")
        checked: { void root.revision; return root.configuration.favoriteFoldersEnabled }
        onToggled: root.configuration.favoriteFoldersEnabled = checked
    }
    Item {
        visible: !root.isPanel
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: hideGridWhenEmpty
        visible: !root.isPanel
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Compact mode:")
        text: i18nd("dev.xarbit.appgrid", "Hide app grid until I start typing")
        checked: { void root.revision; return root.configuration.hideGridWhenEmpty }
        onToggled: root.configuration.hideGridWhenEmpty = checked
    }
    QQC2.Label {
        visible: hideGridWhenEmpty.visible
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        text: i18nd("dev.xarbit.appgrid",
            "Tip: press the Down arrow key to reveal the grid without typing.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    Item { Kirigami.FormData.isSection: true }

    // -- Animations (folded in from the former Animations tab) --

    QQC2.ComboBox {
        id: hoverAnimation
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Icon hover:")
        model: [
            i18nd("dev.xarbit.appgrid", "None"),
            i18nd("dev.xarbit.appgrid", "Shake"),
            i18nd("dev.xarbit.appgrid", "Grow"),
            i18nd("dev.xarbit.appgrid", "Bounce"),
            i18nd("dev.xarbit.appgrid", "Spin"),
            i18nd("dev.xarbit.appgrid", "Shuffle")
        ]
        currentIndex: { void root.revision; return root.configuration.hoverAnimation }
        onActivated: root.configuration.hoverAnimation = currentIndex
    }

    QQC2.CheckBox {
        id: shakeOnOpen
        text: i18nd("dev.xarbit.appgrid", "Animate icons when the launcher opens")
        enabled: hoverAnimation.currentIndex > 0
        checked: { void root.revision; return root.configuration.shakeOnOpen }
        onToggled: root.configuration.shakeOnOpen = checked
    }

    QQC2.Button {
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "System:")
        text: i18nd("dev.xarbit.appgrid", "Configure Animations…")
        icon.name: "settings-configure"
        onClicked: KCM.KCMLauncher.openSystemSettings("kcm_animations")
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Open KDE's animation settings to change the system-wide animation speed (the slider that drives every Plasma animation, this launcher included).")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
