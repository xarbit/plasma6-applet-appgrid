/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the Search settings page. Hosts inject `configuration`
    (read/write) and place this FormLayout inside their own scrollable page.
    Value bindings depend on `revision` so a host can force a re-read after
    revert / load-defaults.
*/

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    // -- Injected context --------------------------------------------------
    property var configuration
    property int revision: 0

    QQC2.CheckBox {
        id: searchAll
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Search:")
        text: i18nd("dev.xarbit.appgrid", "Search all apps regardless of active tab")
        checked: { void root.revision; return root.configuration.searchAll }
        onToggled: root.configuration.searchAll = checked
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: useExtraRunners
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Plugins:")
        text: i18nd("dev.xarbit.appgrid", "Use KDE search plugins (KRunner)")
        checked: { void root.revision; return root.configuration.useExtraRunners }
        onToggled: root.configuration.useExtraRunners = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Includes the calculator, unit conversion, file search, bookmarks, web shortcuts and other KRunner plugins. Use \"Configure Search Plugins\" to choose which are active.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    QQC2.Button {
        text: i18nd("dev.xarbit.appgrid", "Configure Search Plugins…")
        icon.name: "settings-configure"
        enabled: useExtraRunners.checked
        onClicked: KCM.KCMLauncher.openSystemSettings("kcm_plasmasearch")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: searchUsesFrecency
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Ranking:")
        text: i18nd("dev.xarbit.appgrid", "Prefer frequently-used apps in search results (KActivities)")
        checked: { void root.revision; return root.configuration.searchUsesFrecency }
        onToggled: root.configuration.searchUsesFrecency = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Uses system-wide KActivities frecency (frequency + recency) data so apps you've launched a lot lately surface above equally-ranked alternatives. Affects only search results — the app grid keeps its own predictable ordering.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: searchShowsHidden
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Hidden apps:")
        text: i18nd("dev.xarbit.appgrid", "Show hidden applications in search results")
        checked: { void root.revision; return root.configuration.searchShowsHidden }
        onToggled: root.configuration.searchShowsHidden = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Hidden apps stay out of the grid (right-click → Hide Application) and, by default, also out of search results. Turn this on to keep a hidden app findable by name without un-hiding it from the grid.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: searchInlineCompletion
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Completion:")
        text: i18nd("dev.xarbit.appgrid", "Show inline completion as you type")
        checked: { void root.revision; return root.configuration.searchInlineCompletion }
        onToggled: root.configuration.searchInlineCompletion = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Greys the rest of the best matching term after what you've typed (e.g. \"te\" → \"terminal\"); press Tab to accept it.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: showSearchShortcuts
        Kirigami.FormData.label: i18nd("dev.xarbit.appgrid", "Shortcuts:")
        text: i18nd("dev.xarbit.appgrid", "Show the Alt+number badge on search results")
        checked: { void root.revision; return root.configuration.showSearchShortcuts }
        onToggled: root.configuration.showSearchShortcuts = checked
        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid",
            "Each of the first results gets an Alt+1..9 launch shortcut. Turn this off to hide the badges; the shortcuts still work.")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
}
