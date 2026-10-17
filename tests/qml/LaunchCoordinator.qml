/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Launch routing lifted out of GridPanel: the single/bulk launch paths, the
    KActivities broadcast pairing, and the bulk-confirm threshold. Pure logic —
    every UI side effect is a signal the panel handles, so this stays free of the
    search field and the confirm dialogs:

      * closeRequested        — close the launcher after a launch
      * substitutionRequested — paste a runner substitution (calculator result)
                                back into the search field
      * bulkLaunchConfirmRequested — above the threshold, ask before launching

    Injected appsModel / searchModel / plasmoidBridge so it tests with stubs.
*/

import QtQuick

QtObject {
    id: root

    property var appsModel: null
    property var searchModel: null
    property var plasmoidBridge: null

    signal closeRequested()
    signal substitutionRequested(string text)
    signal bulkLaunchConfirmRequested(var sids)

    // Direct fire below the threshold (typical workflow bundles are 2-3 apps);
    // at/above it we prompt, because launching e.g. all 80 installed apps would
    // be an irrecoverable surprise.
    readonly property int bulkLaunchConfirmThreshold: 4

    function launchApp(index) {
        if (!appsModel || index < 0)
            return
        const sid = appsModel.get(index).storageId
        if (sid)
            plasmoidBridge.notifyAppLaunched(sid)
        appsModel.launch(index)
        closeRequested()
    }

    function launchAppByStorageId(sid) {
        if (!appsModel || !sid)
            return
        _launchOneBySid(sid)
        closeRequested()
    }

    // Launch without closing, e.g. one member of a folder's "Launch All".
    function launchAppByStorageIdNoClose(sid) {
        if (!appsModel || !sid)
            return
        _launchOneBySid(sid)
    }

    function launchSearchResult(index) {
        var item = searchModel.get(index)
        if (!item)
            return
        if (item.resultType === "app") {
            launchApp(item.sourceIndex)
            return
        }
        // KRunner UX: calculator hits paste the result back into the search
        // field so the user can keep extending the expression.
        var subst = plasmoidBridge.runner.substitutionText(item.sourceIndex)
        if (subst.length > 0) {
            substitutionRequested(subst)
            return
        }
        if (plasmoidBridge.runner.run(item.sourceIndex))
            closeRequested()
    }

    // One launch step: KActivities broadcast plus the model launch. Shared by
    // the single-sid path and the bulk path so neither repeats the notify/launch
    // pair (notifyAppLaunched is the one-way broadcast that lets other Plasma
    // launchers count AppGrid as a contributing source — not read back).
    function _launchOneBySid(sid) {
        if (!sid)
            return
        plasmoidBridge.notifyAppLaunched(sid)
        appsModel.launchByStorageId(sid)
    }

    function requestBulkLaunch(sids) {
        if (!sids || sids.length === 0)
            return
        if (sids.length >= bulkLaunchConfirmThreshold)
            bulkLaunchConfirmRequested(sids)
        else
            runBulkLaunch(sids)
    }

    function runBulkLaunch(sids) {
        if (!appsModel)
            return
        // _launchOneBySid does not close; run it per sid then close once.
        for (var i = 0; i < sids.length; ++i)
            _launchOneBySid(sids[i])
        closeRequested()
    }

    function runBulkHide(sids) {
        if (!appsModel)
            return
        for (var i = 0; i < sids.length; ++i)
            appsModel.hideByStorageId(sids[i])
    }
}
