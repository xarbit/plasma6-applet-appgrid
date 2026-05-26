/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unified search results list — renders app results and KRunner results
    in a single ListView with continuous keyboard navigation. Sections are
    grouped under Kirigami.ListSectionHeader with per-section counts; the
    list shows a Kirigami.PlaceholderMessage when a search returns nothing.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

ListView {
    id: listView

    property PlasmaComponents.TextField searchField: null
    property real iconSize: Kirigami.Units.iconSizes.huge
    property bool showDividers: true

    signal launched(int index)
    signal contextMenuRequested(int index, string storageId, string desktopFile)

    clip: true
    reuseItems: true

    WheelScroller { target: listView }
    currentIndex: count > 0 ? 0 : -1
    keyNavigationEnabled: true

    property bool animateHighlight: true
    // Keyboard nav animates the highlight; hover-driven selects snap so the
    // highlight tracks the cursor crisply across rows.
    property bool _suppressHighlightAnim: false
    highlightMoveDuration: (animateHighlight && !_suppressHighlightAnim)
        ? Kirigami.Units.shortDuration : 0
    highlightResizeDuration: 0
    // One themed renderer per row, so hover and keyboard-focus never
    // stack visually (would otherwise reveal a corner mismatch).
    highlight: PlasmaExtras.Highlight {}

    // Snap back to the top whenever results change; a hover-set
    // currentIndex breaks the `count > 0 ? 0 : -1` binding, so without
    // this Enter would launch a stale row instead of the new top match.
    // The list-change timestamp blocks hover-select for a short window
    // around scrolls and result-set updates so rows passing or appearing
    // under a stationary cursor don't claim the highlight.
    property double _lastListChange: 0
    onContentYChanged: _lastListChange = Date.now()
    onCountChanged: {
        _lastListChange = Date.now()
        if (count > 0)
            currentIndex = 0
    }

    function _tryHoverSelect(row, pointerY, idx) {
        if (Date.now() - _lastListChange < 100)
            return

        const top = row.mapToItem(listView, 0, 0).y
        const bottom = row.mapToItem(listView, 0, row.height).y
        const clipped = top < 0 || bottom > height
        const mouseYInList = row.mapToItem(listView, 0, pointerY).y
        const inBottomEdge = mouseYInList > height - Kirigami.Units.smallSpacing * 2

        if (!clipped || !inBottomEdge) {
            _suppressHighlightAnim = true
            currentIndex = idx
            Qt.callLater(() => _suppressHighlightAnim = false)
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

    function _sectionLabel(section) {
        const m = listView.model
        if (section === "app")
            return i18nd("dev.xarbit.appgrid", "Applications") +
                   (m ? " (" + m.appResultCount + ")" : "")
        if (section === "runner")
            return i18nd("dev.xarbit.appgrid", "Search Plugins") +
                   (m ? " (" + m.runnerResultCount + ")" : "")
        return section
    }

    section.property: "resultType"
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
        visible: number > 0
        implicitWidth: badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                       Kirigami.Theme.highlightColor.g,
                       Kirigami.Theme.highlightColor.b, 0.15)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.2)
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

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        icon.name: "system-search-symbolic"
        text: searchField && searchField.text.length > 0
              ? i18nd("dev.xarbit.appgrid", "No results for \"%1\"", searchField.text)
              : ""
        visible: listView.count === 0 && searchField && searchField.text.length > 0
    }

    Keys.onReturnPressed: if (currentIndex >= 0) listView.launched(currentIndex)
    Keys.onEnterPressed: if (currentIndex >= 0) listView.launched(currentIndex)

    Keys.onPressed: function(event) {
        if (event.modifiers & Qt.AltModifier) {
            const num = event.key - Qt.Key_0
            if (num >= 1 && num <= 9 && num <= count) {
                launched(num - 1)
                event.accepted = true
                return
            }
        }

        switch (event.key) {
        case Qt.Key_PageDown: pageDown(); event.accepted = true; return
        case Qt.Key_PageUp:   pageUp();   event.accepted = true; return
        case Qt.Key_Home:     goHome();   event.accepted = true; return
        case Qt.Key_End:      goEnd();    event.accepted = true; return
        }

        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            searchField.forceActiveFocus()
            searchField.text = searchField.text.slice(0, -1)
            event.accepted = true
        } else if (event.text.length > 0 && !event.modifiers) {
            searchField.forceActiveFocus()
            searchField.text += event.text
            event.accepted = true
        }
    }

    Keys.onDownPressed: {
        if (currentIndex < count - 1)
            currentIndex++
    }

    Keys.onUpPressed: {
        if (currentIndex > 0)
            currentIndex--
        else if (searchField)
            searchField.forceActiveFocus()
    }

    Keys.onTabPressed: {
        if (currentIndex < count - 1)
            currentIndex++
        else
            currentIndex = 0
    }

    Keys.onBacktabPressed: {
        if (currentIndex > 0)
            currentIndex--
        else
            currentIndex = count - 1
    }

    Keys.onEscapePressed: {
        if (searchField) searchField.forceActiveFocus()
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
        readonly property color labelColor: highlighted
            ? Kirigami.Theme.highlightedTextColor
            : Kirigami.Theme.textColor

        Accessible.name: (model.shortcutNumber > 0 ? "Alt+" + model.shortcutNumber + ": " : "") + (model.name || "")
        Accessible.role: Accessible.Button
        Accessible.description: model.subtext || ""
        Accessible.focusable: true

        onClicked: listView.launched(model.index)

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: listView.contextMenuRequested(model.index, model.storageId || "", model.desktopFile || "")
        }

        HoverHandler {
            id: rowHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                listView._tryHoverSelect(resultDelegate, point.position.y, model.index)
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            ShortcutBadge { number: model.shortcutNumber }

            ShadowedIcon {
                implicitWidth: listView.iconSize
                implicitHeight: listView.iconSize
                source: model.iconName || "application-x-executable"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: model.name || ""
                        elide: Text.ElideRight
                        color: resultDelegate.labelColor
                    }
                    InfoChip {
                        visible: model.installSource !== undefined
                                 && model.installSource.length > 0
                                 && model.installSource !== "System"
                        text: model.installSource || ""
                    }
                    InfoChip {
                        text: model.category || i18nd("dev.xarbit.appgrid", "Application")
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: model.subtext || ""
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    visible: text.length > 0
                    color: resultDelegate.labelColor
                }
            }

            PlasmaComponents.ToolButton {
                visible: resultDelegate.highlighted
                Layout.alignment: Qt.AlignVCenter
                icon.name: "overflow-menu"
                PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "More options")
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: listView.contextMenuRequested(model.index,
                                                        model.storageId || "",
                                                        model.desktopFile || "")
            }
        }

    }
}
