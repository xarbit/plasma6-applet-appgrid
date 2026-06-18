/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigSearchContent. A `cfg_<key>` property
    per setting drives Plasma's dirty-tracking and the KConfigXT flush (#191); the
    shared Content writes to the buffer QtObject so edits stay staged until
    Apply/OK.
*/

import QtQuick

import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_searchAll: buffer.searchAll
    property alias cfg_useExtraRunners: buffer.useExtraRunners
    property alias cfg_searchUsesFrecency: buffer.searchUsesFrecency
    property alias cfg_searchShowsHidden: buffer.searchShowsHidden
    property alias cfg_searchInlineCompletion: buffer.searchInlineCompletion
    property alias cfg_showSearchShortcuts: buffer.showSearchShortcuts

    QtObject {
        id: buffer
        property bool searchAll
        property bool useExtraRunners
        property bool searchUsesFrecency
        property bool searchShowsHidden
        property bool searchInlineCompletion
        property bool showSearchShortcuts
    }

    ConfigSearchContent {
        configuration: buffer
    }
}
