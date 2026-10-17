/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The category bar's scrolling strip of category tabs, with a scroll arrow
    reserved at each edge when the tabs overflow. It pages by tab boundaries,
    takes the wheel, and scrolls a selected tab into view; the scroll
    geometry itself is CategoryScroll's (tested). The bar (`bar`) gives the
    tabs, their look and the hover handling.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../js/categoryscroll.js" as CategoryScroll

Item {
    id: strip

    // The CategoryBar this strip belongs to.
    required property var bar

    // Right-click on a category tab.
    signal contextMenuRequested(string name)

    // Effective viewport width for rightward-scroll math — see
    // CategoryScroll.viewportAfterRightScroll for the why.
    function _viewportWidthAfterRightScroll() {
        return CategoryScroll.viewportAfterRightScroll(catFlick.width, catFlick.contentX, bar.scrollArrowWidth)
    }

    // Live delegate rects in visual order, for the page-target math (null for
    // a not-yet-realised delegate; CategoryScroll skips those).
    function _itemRects() {
        const rects = []
        for (let i = 0; i < catRepeater.count; i++) {
            const it = catRepeater.itemAt(i)
            rects.push(it ? { x: it.x, width: it.width } : null)
        }
        return rects
    }

    // Furthest valid offset for `target`, clamped against the viewport it will land
    // in (CategoryScroll.clampToReserve) — not the current one — so an animated move
    // can't overshoot once a reserve collapses mid-glide and the contentX animation
    // outruns the re-clamp (#172).
    function _clampTarget(target) {
        return CategoryScroll.clampToReserve(target, width, catRow.implicitWidth, bar.scrollArrowWidth)
    }

    // Single landing-point for wheel, arrow clicks, alt+arrow, reset. Lands in-frame
    // (contentX Behavior suppressed) so categories track every input source snappily.
    function setContentX(target) {
        catFlick._suppressContentXAnim = true
        catFlick.contentX = _clampTarget(target)
        catFlick._suppressContentXAnim = false
    }

    // Glide to the start (the All tab was clicked).
    function scrollToStart() {
        catFlick.contentX = _clampTarget(0)
    }

    // Page by ~one viewport per click; CategoryScroll.pageTarget gives one
    // tab-boundary-aligned rule for both directions (right lands the last tab flush,
    // left the first). The move animates so the page and the arrow inset ease in
    // together.
    function pageRight() {
        catFlick.contentX = _clampTarget(CategoryScroll.pageTarget(_itemRects(), catFlick.contentX,
            _viewportWidthAfterRightScroll(), catFlick.contentWidth, 1))
    }
    function pageLeft() {
        catFlick.contentX = _clampTarget(CategoryScroll.pageTarget(_itemRects(), catFlick.contentX,
            catFlick.width, catFlick.contentWidth, -1))
    }

    // Bring the tab of category @p name into view; "" (All) scrolls to the start.
    function scrollToTab(name) {
        if (name === "") {
            setContentX(0)
            return
        }
        const names = bar.categoryList
        for (let i = 0; i < catRepeater.count && i < names.length; i++) {
            const item = catRepeater.itemAt(i)
            if (item && names[i] === name) {
                const target = CategoryScroll.ensureVisibleTarget(item.x, item.width,
                    catFlick.contentX, catFlick.width, _viewportWidthAfterRightScroll(),
                    Kirigami.Units.smallSpacing)
                if (target !== null)
                    setContentX(target)
                return
            }
        }
    }

    // The category whose tab is under the pointer, or "".
    function hoveredCategory() {
        const names = bar.categoryList
        for (let i = 0; i < catRepeater.count && i < names.length; i++) {
            const it = catRepeater.itemAt(i)
            if (it && it.hovered)
                return names[i]
        }
        return ""
    }

    implicitHeight: strip.bar.buttonHeight

    // A plain Item carries the strip's geometry; the Flickable fills it. The
    // arrows reserve their width by insetting this Item (x for the left, a
    // narrower width for the right), NOT by insetting the Flickable directly —
    // a width bound on the Flickable is clobbered by its own internal geometry,
    // leaving x and width disagreeing on the reserve, the strip overrunning
    // strip over the favorites / off the edge. The whole geometry comes from
    // ONE CategoryScroll.reserveGeometry call (leaf inputs only — contentX,
    // strip.width, natural content width), so the two reserves are always
    // consistent; a split across separate bindings can land half-stale on a
    // jump and strand the strip short of the edge (#172).
    Item {
        id: catViewport
        readonly property var geom: CategoryScroll.reserveGeometry(
            catFlick.contentX, strip.width, catRow.implicitWidth, strip.bar.scrollArrowWidth)

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: geom.leftReserve
        width: geom.viewport

        Flickable {
            id: catFlick
            anchors.fill: parent

            contentWidth: catRow.width
            contentHeight: strip.bar.buttonHeight
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            // A reserve appearing narrows the viewport, which can leave contentX past
            // the new maxX. Clamp only that overscroll — like the left edge self-correcting
            // at 0, never an unconditional re-anchor (writing contentX from width every
            // change is the feedback that froze / looped the bar). Deferred on purpose:
            // the left and right margins update in separate binding passes, so one
            // contentX change flickers through a transient full-width frame (both margins
            // briefly 0) whose tiny maxX would clamp contentX short. Run after the cascade
            // settles, against the final width (#172).
            property bool _suppressContentXAnim: false
            onWidthChanged: Qt.callLater(_clampToBounds)
            function _clampToBounds() {
                const maxX = CategoryScroll.maxContentX(contentWidth, width)
                if (contentX > maxX) {
                    _suppressContentXAnim = true
                    contentX = maxX
                    _suppressContentXAnim = false
                }
            }

            // Edge-settling guard for #113: once a wheel lands on either edge,
            // swallow follow-up wheels for a short window so rapid scrolling
            // can't re-target the contentX animation and overshoot past max.
            property bool _wheelEdgeSettling: false
            Timer {
                id: wheelEdgeSettlingTimer
                interval: Math.max(Kirigami.Units.shortDuration, 120)
                onTriggered: catFlick._wheelEdgeSettling = false
            }

            Kirigami.WheelHandler {
                target: catFlick
                onWheel: function(wheel) {
                    wheel.accepted = true
                    strip.bar.hover.wheel()
                    if (catFlick._wheelEdgeSettling)
                        return
                    const raw = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                    const delta = CategoryScroll.clampWheelDelta(raw, catFlick.width,
                        strip.bar.scrollArrowWidth * 4)
                    strip.setContentX(catFlick.contentX - delta)
                    const maxX = CategoryScroll.maxContentX(catFlick.contentWidth, catFlick.width)
                    if (catFlick.contentX === 0 || catFlick.contentX === maxX) {
                        catFlick._wheelEdgeSettling = true
                        wheelEdgeSettlingTimer.restart()
                    }
                }
            }

            Behavior on contentX {
                enabled: !catFlick._suppressContentXAnim && Kirigami.Units.longDuration > 0
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                id: catRow
                // Icon-only: fill the viewport (the fillWidth buttons trim their
                // padding to absorb a slightly-wider icon instead of flipping to a
                // scroll), but never below iconRowMinWidth — past that the row
                // overflows so the icons scroll instead of overlapping. Other modes
                // grow with their content and scroll as before.
                width: strip.bar.tabsIconOnly
                       ? Math.max(catFlick.width, strip.bar.iconRowMinWidth)
                       : Math.max(implicitWidth, catFlick.width)
                height: parent.height
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    id: catRepeater
                    model: strip.bar.categoryList
                    delegate: CategoryTabButton {
                        bar: strip.bar
                        onContextMenuRequested: name => {
                            catContextMenu.categoryName = name
                            catContextMenu.popup()
                        }
                    }
                }
            }
        }
    }

    // -- Scroll arrows, in the reserved margin at each catFlick edge --
    CategoryScrollArrow {
        id: scrollLeftBtn
        bar: strip.bar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        scrollable: catViewport.geom.leftReserve > 0
        icon.name: "arrow-left"
        pageAction: () => strip.pageLeft()
        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories left")
    }
    CategoryScrollArrow {
        id: scrollRightBtn
        bar: strip.bar
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        scrollable: catViewport.geom.rightShown
        icon.name: "arrow-right"
        pageAction: () => strip.pageRight()
        Accessible.name: i18nd("dev.xarbit.appgrid", "Scroll categories right")
    }
}
