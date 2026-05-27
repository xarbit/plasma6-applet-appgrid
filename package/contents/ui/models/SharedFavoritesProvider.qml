/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin wrapper around KAStatsFavoritesModel. Lives in its own file so the
    private.kicker import only loads when shared favorites are enabled — on
    systems without the Kicker plugin a Loader pointing at this file will
    fail without crashing the rest of the plasmoid.
*/

import QtQuick

import org.kde.plasma.private.kicker as Kicker

Kicker.KAStatsFavoritesModel {
    // -1 = unlimited; default caps the list.
    maxFavorites: -1
}
