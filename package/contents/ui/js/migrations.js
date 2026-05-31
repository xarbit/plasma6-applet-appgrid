// SPDX-FileCopyrightText: 2026 AppGrid Contributors
// SPDX-License-Identifier: GPL-2.0-or-later
//
// One-shot upgrade migrations. Each helper is idempotent: it inspects a
// dedicated *Migrated flag in Plasmoid.configuration and bails out if the
// migration has already run. Call sites stay one-liners.
//
// Import as:
//     import "migrations.js" as Migrations

.pragma library
.import "constants.js" as Const
.import "headeractions.js" as HeaderActions

// Legacy showSessionButtons toggle hid the whole power row. Carry that
// intent into the per-button hidden list introduced in 1.8.0.
function migratePowerButtons(cfg) {
    if (cfg.powerButtonsMigrated)
        return
    if (cfg.showSessionButtons === false)
        cfg.powerButtonsHidden =
            ["sleep", "restart", "shutdown", "session", "lock", "logout", "switchuser"]
    cfg.powerButtonsMigrated = true
}

// 1.9.0 unified the power/session/update buttons into one configurable
// headerActions layout. Fold the legacy powerButtonOrder/powerButtonsHidden
// into it once so upgrading users keep their arrangement (#111). Run after
// migratePowerButtons, which populates powerButtonsHidden this reads.
function migrateHeaderActions(cfg) {
    if (cfg.headerActionsMigrated)
        return
    cfg.headerActions =
        HeaderActions.migrateFromLegacy(cfg.powerButtonOrder, cfg.powerButtonsHidden)
    cfg.headerActionsMigrated = true
}

// 1.8.0 changed the default launcher icon from start-here-kde-symbolic to
// the bundled dev.xarbit.appgrid. KConfigXT does not persist defaults, so
// users upgrading from 1.7.x who never picked an icon would silently see
// the new one. Pin them to the prior default once (#122).
function migrateLauncherIcon(cfg) {
    if (cfg.iconMigratedFrom17)
        return
    const hasPriorState =
        (cfg.knownApps && cfg.knownApps.length > 0)
        || (cfg.launchCounts && cfg.launchCounts.length > 0)
        || (cfg.favoriteApps && cfg.favoriteApps.length > 0)
    if (hasPriorState && !cfg.useCustomButtonImage && cfg.icon === Const.PLUGIN_ID_CENTER)
        cfg.icon = "start-here-kde-symbolic"
    cfg.iconMigratedFrom17 = true
}
