/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for configbuffer.js — the buffer/apply value math behind the
    standalone settings window (ConfigWindow.qml). The headline case is the
    concurrent-write race (#4): the launcher live-writes hiddenApps (right-click
    "Hide Application") while the settings window is open; Apply must NOT clobber
    that with the stale buffer value. Plain JS stand-ins stand in for the
    live/buffer AppGridConfig (each setting is `obj[key]`).
*/

import QtQuick
import QtTest
import "configbuffer.js" as ConfigBuffer

TestCase {
    name: "ConfigBuffer"

    readonly property var keys: ["gridColumns", "hiddenApps", "sortMode"]
    readonly property var emptyDefaults: ({ "hiddenApps": [] })

    function _live() { return ({ gridColumns: 6, hiddenApps: ["a"], sortMode: 0 }) }
    function _json(v) { return JSON.stringify(v) }

    // sync copies live -> buffer and returns a baseline equal to live.
    function test_syncCopiesAndBaselines() {
        var live = _live(), buffer = ({})
        var baseline = ConfigBuffer.syncFromLive(buffer, live, keys)
        compare(buffer.gridColumns, 6)
        compare(_json(buffer.hiddenApps), _json(["a"]))
        compare(_json(baseline), _json(live))
    }

    // dirty is false straight after a sync, true once the buffer diverges.
    function test_dirtyTracksBufferVsLive() {
        var live = _live(), buffer = ({})
        ConfigBuffer.syncFromLive(buffer, live, keys)
        verify(!ConfigBuffer.isDirty(buffer, live, keys), "clean after sync")
        buffer.gridColumns = 8
        verify(ConfigBuffer.isDirty(buffer, live, keys), "dirty after edit")
    }

    // The race (#4): user edits gridColumns; the launcher concurrently appends
    // to live.hiddenApps. Apply writes ONLY the user-edited key, so the
    // concurrent hide survives instead of being reverted to the buffer value.
    function test_applyPreservesConcurrentLiveWrite() {
        var live = _live(), buffer = ({})
        var baseline = ConfigBuffer.syncFromLive(buffer, live, keys)

        buffer.gridColumns = 8                 // user edit in the settings window
        live.hiddenApps = ["a", "b"]           // launcher hides "b" meanwhile

        var applied = ConfigBuffer.applyChanged(buffer, live, baseline, keys)

        compare(_json(applied), _json(["gridColumns"]), "only the edited key applied")
        compare(live.gridColumns, 8, "user edit committed")
        compare(_json(live.hiddenApps), _json(["a", "b"]),
                "concurrent hide preserved, not clobbered by stale buffer")
    }

    // A key the user DID edit is committed even if it is one both sides touch.
    function test_applyCommitsEditedSharedKey() {
        var live = _live(), buffer = ({})
        var baseline = ConfigBuffer.syncFromLive(buffer, live, keys)
        buffer.hiddenApps = ["a", "z"]         // user unhid nothing, added z
        var applied = ConfigBuffer.applyChanged(buffer, live, baseline, keys)
        compare(_json(applied), _json(["hiddenApps"]))
        compare(_json(live.hiddenApps), _json(["a", "z"]))
    }

    // Nothing applied when the buffer matches the baseline (no user edits).
    function test_applyNoopWhenUnchanged() {
        var live = _live(), buffer = ({})
        var baseline = ConfigBuffer.syncFromLive(buffer, live, keys)
        var applied = ConfigBuffer.applyChanged(buffer, live, baseline, keys)
        compare(applied.length, 0)
    }

    // defaultFor / atDefaults / loadDefaults: emptyDefaults override wins,
    // otherwise the generated defaultXValue mirror on the buffer is used.
    function test_defaultsViaTableAndGeneratedMirror() {
        var buffer = ({
            gridColumns: 6, hiddenApps: ["a"], sortMode: 2,
            defaultGridColumnsValue: 7, defaultSortModeValue: 0
        })
        compare(ConfigBuffer.defaultFor(buffer, "gridColumns", emptyDefaults), 7)
        compare(_json(ConfigBuffer.defaultFor(buffer, "hiddenApps", emptyDefaults)), _json([]))
        verify(!ConfigBuffer.atDefaults(buffer, keys, emptyDefaults), "not at defaults yet")

        ConfigBuffer.loadDefaults(buffer, keys, emptyDefaults)
        compare(buffer.gridColumns, 7)
        compare(buffer.sortMode, 0)
        compare(_json(buffer.hiddenApps), _json([]))
        verify(ConfigBuffer.atDefaults(buffer, keys, emptyDefaults), "at defaults after load")
    }

    // The baseline snapshot detaches list values: mutating the live list in
    // place must not retroactively change a snapshot taken earlier.
    function test_snapshotDetachesLists() {
        var live = _live()
        var snap = ConfigBuffer.snapshot(live, keys)
        live.hiddenApps.push("mutated-in-place")
        compare(_json(snap.hiddenApps), _json(["a"]), "snapshot unaffected by in-place mutation")
    }
}
