/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unified search results list — renders app results and KRunner results
    in a single ListView with continuous keyboard navigation. Sections are
    grouped under Kirigami.ListSectionHeader with per-section counts; the
    list shows a centered icon + label when a search returns nothing.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

import "../controllers"
import "../widgets"
import "../js/themecolors.js" as ThemeColors
import "../js/constants.js" as Const

ListView {
    id: listView

    property PlasmaComponents.TextField searchField: null
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Caller-supplied font multiplier for the result name Label so it
    // stays proportional with the user's icon-size preference. Subtext
    // sticks to Kirigami.Theme.smallFont (unaffected — it's secondary
    // info and shrinks too far below 1.0).
    property real fontScale: 1.0
    property bool showDividers: true
    property bool shadowEnabled: false
    // Show the Alt+N launch-shortcut badge on each row. The shortcut still
    // works when hidden — this only drops the visual label (#165).
    property bool showShortcuts: true

    signal launched(int index)
    signal contextMenuRequested(int index, string storageId, string desktopFile)
    signal runnerContextMenuRequested(int index)

    clip: true
    reuseItems: true

    currentIndex: count > 0 ? 0 : -1

    property bool animateHighlight: true
    // Keyboard nav animates the highlight; hover-driven selects snap so the
    // highlight tracks the cursor crisply across rows.
    property bool _suppressHighlightAnim: false
    readonly property var _clearSuppressHighlightAnim: function() {
        _suppressHighlightAnim = false
    }
    highlightMoveDuration: (animateHighlight && !_suppressHighlightAnim)
        ? Kirigami.Units.shortDuration : 0
    highlightResizeDuration: 0
    // One themed renderer per row, so hover and keyboard-focus never
    // stack visually (would otherwise reveal a corner mismatch).
    highlight: PlasmaExtras.Highlight {}

    // --- Hover-select gating ---
    // HoverGate decides whether a pointChanged event should claim the
    // highlight; see HoverGate.qml. Count snap re-establishes the top
    // match on every search-query change because a hover-set currentIndex
    // breaks the `count > 0 ? 0 : -1` binding.

    HoverGate { id: hoverGate }

    WheelScroller {
        target: listView
        onWheel: hoverGate.markWheel()
    }

    onCountChanged: {
        if (count > 0 && searchField && searchField.text.length > 0)
            currentIndex = 0
    }

    function _tryHoverSelect(row, pointerY, idx, scenePos) {
        if (!hoverGate.allows(scenePos))
            return

        const top = row.mapToItem(listView, 0, 0).y
        const bottom = row.mapToItem(listView, 0, row.height).y
        const clipped = top < 0 || bottom > height
        const mouseYInList = row.mapToItem(listView, 0, pointerY).y
        const inBottomEdge = mouseYInList > height - Kirigami.Units.smallSpacing * 2

        if ((!clipped || !inBottomEdge) && currentIndex !== idx) {
            _suppressHighlightAnim = true
            currentIndex = idx
            Qt.callLater(_clearSuppressHighlightAnim)
        }
    }

    // PgDn lands on the partially-clipped bottom row so the user never
    // loses a result; if the bottom fits fully, step past it. PgUp goes
    // the symmetric distance back from the current top, so a PgDn/PgUp
    // pair returns to the previous viewport.
    function pageDown() {
        if (count === 0) return
        const { top, bottom } = _viewportEdges()
        const next = _rowExceedsViewport(bottom, true)
            ? bottom
            : Math.min(count - 1, bottom + 1)
        _navTo(next)
    }
    function pageUp() {
        if (count === 0) return
        const { top, bottom } = _viewportEdges()
        const next = _rowExceedsViewport(top, false)
            ? top
            : Math.max(0, top - Math.max(1, bottom - top))
        _navTo(next)
    }
    function goHome() {
        if (count === 0) return
        currentIndex = 0
        positionViewAtBeginning()
    }
    function goEnd() {
        if (count === 0) return
        currentIndex = count - 1
        positionViewAtEnd()
    }

    // indexAt() returns -1 when the probe pixel is past the content,
    // which happens whenever the list is shorter than the viewport.
    // Clamp so navigation still works in that case.
    function _viewportEdges() {
        let top = indexAt(width / 2, contentY)
        let bottom = indexAt(width / 2, contentY + height - 1)
        if (top < 0) top = 0
        if (bottom < 0) bottom = count - 1
        return { top, bottom }
    }
    function _rowExceedsViewport(idx, atBottom) {
        const item = itemAtIndex(idx)
        if (!item) return false
        return atBottom
            ? item.y + item.height > contentY + height
            : item.y < contentY
    }
    function _navTo(idx) {
        if (idx === currentIndex) return
        currentIndex = idx
        positionViewAtIndex(idx, ListView.Beginning)
    }

    // Section-key sentinels, shared with UnifiedSearchModel::data (CategoryRole):
    // our app rows carry _appSection, KRunner rows are _plasmaPrefix + their
    // category. Labels: "Applications" for ours; "Plasma Plugins (Files)" per
    // runner, or just "Plasma Plugins" when the runner gives no category.
    readonly property string _appSection: "applications"
    readonly property string _plasmaPrefix: "plasma:"
    function _sectionLabel(section) {
        if (section === _appSection)
            return i18nd("dev.xarbit.appgrid", "Applications")
        const cat = section.substring(_plasmaPrefix.length)
        return cat.length > 0
            ? i18nd("dev.xarbit.appgrid", "Plasma Plugins (%1)", cat)
            : i18nd("dev.xarbit.appgrid", "Plasma Plugins")
    }

    section.property: "category"
    section.criteria: ViewSection.FullString
    section.delegate: Kirigami.ListSectionHeader {
        width: listView.width
        text: listView._sectionLabel(section)
    }

    component InfoChip: Kirigami.Chip {
        checkable: false
        closable: false
        interactive: false
        labelItem.font: Kirigami.Theme.smallFont
        leftPadding: Kirigami.Units.smallSpacing
        rightPadding: Kirigami.Units.smallSpacing
        topPadding: 0
        bottomPadding: 0
        implicitHeight: labelItem.implicitHeight + Kirigami.Units.smallSpacing
    }

    component ShortcutBadge: Rectangle {
        property int number: 0
        visible: number > 0 && listView.showShortcuts
        implicitWidth: badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        radius: Kirigami.Units.cornerRadius
        color: ThemeColors.tint(Kirigami.Theme.highlightColor, 0.15)
        border.width: 1
        border.color: ThemeColors.tint(Kirigami.Theme.textColor, 0.2)
        Accessible.ignored: true

        PlasmaComponents.Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: "Alt+" + parent.number
            font.bold: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }
    }

    EmptyStateMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: listView.count === 0 && searchField && searchField.text.length > 0
        iconSource: "system-search-symbolic"
        text: searchField && searchField.text.length > 0
              ? i18nd("dev.xarbit.appgrid", "No results for \"%1\"", searchField.text)
              : ""
    }

    delegate: PlasmaComponents.ItemDelegate {
        id: resultDelegate
        width: listView.width
        height: Math.max(listView.iconSize, contentItem.implicitHeight) + Kirigami.Units.smallSpacing * 2
        leftPadding: Kirigami.Units.largeSpacing
        rightPadding: Kirigami.Units.largeSpacing
        highlighted: listView.currentIndex === model.index
        // PlasmaExtras.Highlight on the ListView draws all row backgrounds.
        background: null
        // text stays at textColor on selection (the
        // PlasmaExtras.Highlight tint is translucent, not an opaque
        // highlightColor fill), only press flips to highlightedTextColor.
        readonly property color labelColor: down
            ? Kirigami.Theme.highlightedTextColor
            : Kirigami.Theme.textColor

        Accessible.name: (model.shortcutNumber > 0 ? "Alt+" + model.shortcutNumber + ": " : "") + (model.name || "")
                         + (resultDelegate.itemHidden ? ", " + i18nd("dev.xarbit.appgrid", "hidden") : "")
        Accessible.role: Accessible.Button
        Accessible.description: model.subtext || ""
        Accessible.focusable: true

        onClicked: listView.launched(model.index)

        // Runner rows that resolve to a .desktop file (KRunner's services
        // runner returns installed apps as runner rows) get the same
        // App context menu as native app rows — they ARE apps, just
        // surfaced through a different model lane.
        // A jump-list action row resolves the parent app's storage id, but it must
        // route to the runner menu so the ACTION (not the plain app) is favourited.
        readonly property bool actsLikeApp: (model.resultType === "app"
                                             || (model.storageId || "").length > 0)
                                            && model.isRunnerAction !== true

        // Hidden apps surface in results only with "show hidden in search" on;
        // flag them so the row dims and shows the hidden indicator below.
        readonly property bool itemHidden: model.isHidden === true

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: {
                if (resultDelegate.actsLikeApp) {
                    listView.contextMenuRequested(model.index,
                                                  model.storageId || "",
                                                  model.desktopFile || "")
                } else {
                    listView.runnerContextMenuRequested(model.index)
                }
            }
        }

        HoverHandler {
            id: rowHover
            cursorShape: Qt.PointingHandCursor
            // pointChanged also catches cursor motion within the row, so
            // the select retries once the list-change gate releases —
            // hoveredChanged alone wouldn't re-fire in that case.
            onPointChanged: if (hovered)
                listView._tryHoverSelect(resultDelegate, point.position.y,
                                         model.index, point.scenePosition)
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            opacity: resultDelegate.itemHidden ? Const.HIDDEN_RESULT_OPACITY : 1.0

            ShortcutBadge { number: model.shortcutNumber }

            ShadowedIcon {
                implicitWidth: listView.iconSize
                implicitHeight: listView.iconSize
                source: model.iconName || Const.DEFAULT_ICON
                shadowEnabled: listView.shadowEnabled
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    // KRunner-style: a result flagged multiLine (the dictionary
                    // runner and similar) wraps to its full text; everything else
                    // stays one elided line. The line count is fixed per result —
                    // it doesn't change on selection, so selecting a row never
                    // shifts the others (no jitter, no skipped rows) (#189).
                    WrappingLabel {
                        text: model.name || ""
                        lines: model.multiLine ? 8 : 1
                        color: resultDelegate.labelColor
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * listView.fontScale
                    }
                    // Top-aligned so the indicator and pills stay beside the first
                    // line when a long result name wraps to several lines (#183),
                    // rather than floating to the middle of the grown row.
                    // Hidden indicator, paired with the row dim.
                    Kirigami.Icon {
                        visible: resultDelegate.itemHidden
                        source: "view-hidden"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                        Layout.alignment: Qt.AlignTop
                    }
                    // Source badge only (flatpak/snap/…); shown just for non-system
                    // sources, so most rows carry no pill. The per-row category
                    // pill was dropped (#189): redundant with the section header,
                    // and it stole width from long result text.
                    InfoChip {
                        visible: model.installSource !== undefined
                                 && model.installSource.length > 0
                                 && model.installSource !== "System"
                        text: model.installSource || ""
                        Layout.alignment: Qt.AlignTop
                    }
                }

                // Secondary line — some runners carry the detail here instead of
                // the name; wraps with the name when the result is multiLine.
                WrappingLabel {
                    text: model.subtext || ""
                    lines: model.multiLine ? 8 : 1
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    visible: text.length > 0
                    color: resultDelegate.labelColor
                }
            }

            PlasmaComponents.ToolButton {
                id: overflowButton
                // App context menu (Pin / Add to Desktop / Hide / …) for
                // anything app-shaped — native AppFilterModel rows AND
                // runner rows whose .desktop URL we resolved a storageId
                // out of. Runner-action overflow only for runner rows
                // that actually expose secondary actions (calculator yes,
                // most other runners no — empty menu otherwise).
                visible: resultDelegate.highlighted
                         && (resultDelegate.actsLikeApp
                             || model.isRunnerAction === true
                             || (model.runnerActionsCount || 0) > 0)
                Layout.alignment: Qt.AlignVCenter
                icon.name: "overflow-menu"
                PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "More options")
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: {
                    if (resultDelegate.actsLikeApp) {
                        listView.contextMenuRequested(model.index,
                                                      model.storageId || "",
                                                      model.desktopFile || "")
                    } else {
                        listView.runnerContextMenuRequested(model.index)
                    }
                }
            }
        }

    }
}
