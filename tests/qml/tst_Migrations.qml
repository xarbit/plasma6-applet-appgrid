/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for migrations.js — one-shot config upgrades. Each helper
    must (a) leave state alone on a second call, (b) flip its done-flag
    on every path so it doesn't re-run, and (c) survive shape-mismatch
    inputs without dropping the user's other config.
*/

import QtQuick
import QtTest
import "migrations.js" as Migrations

TestCase {
    name: "Migrations"

    // --- migratePowerButtons ---

    function test_powerButtonsAlreadyMigratedIsNoop() {
        var cfg = {
            powerButtonsMigrated: true,
            showSessionButtons: false,
            powerButtonsHidden: ["existing"]
        }
        Migrations.migratePowerButtons(cfg)
        compare(cfg.powerButtonsHidden, ["existing"])
        verify(cfg.powerButtonsMigrated)
    }

    function test_powerButtonsHidesAllWhenLegacyOff() {
        var cfg = { showSessionButtons: false }
        Migrations.migratePowerButtons(cfg)
        compare(cfg.powerButtonsHidden,
                ["sleep", "restart", "shutdown",
                 "session", "lock", "logout", "switchuser"])
        verify(cfg.powerButtonsMigrated)
    }

    function test_powerButtonsLeavesHiddenAloneWhenLegacyOn() {
        var cfg = { showSessionButtons: true }
        Migrations.migratePowerButtons(cfg)
        verify(cfg.powerButtonsHidden === undefined)
        verify(cfg.powerButtonsMigrated)
    }

    function test_powerButtonsFlagsEvenWithoutLegacyValue() {
        // Fresh install: showSessionButtons is undefined, not false.
        // The flag must still flip so the helper doesn't re-run.
        var cfg = {}
        Migrations.migratePowerButtons(cfg)
        verify(cfg.powerButtonsHidden === undefined)
        verify(cfg.powerButtonsMigrated)
    }

    // --- migrateHeaderActions ---

    function test_headerActionsAlreadyMigratedIsNoop() {
        var cfg = {
            headerActionsMigrated: true,
            headerActions: ["lock:bar"],
            powerButtonOrder: ["sleep"], powerButtonsHidden: []
        }
        Migrations.migrateHeaderActions(cfg)
        compare(cfg.headerActions, ["lock:bar"])
        verify(cfg.headerActionsMigrated)
    }

    function test_headerActionsFoldsLegacyOrderAndHidden() {
        var cfg = {
            powerButtonOrder: ["sleep", "session"],
            powerButtonsHidden: ["logout"]
        }
        Migrations.migrateHeaderActions(cfg)
        verify(cfg.headerActions.indexOf("sleep:bar") >= 0)
        verify(cfg.headerActions.indexOf("lock:menu") >= 0)
        verify(cfg.headerActions.indexOf("logout:off") >= 0)
        verify(cfg.headerActionsMigrated)
    }

    function test_headerActionsFlagsOnFreshInstall() {
        // Empty legacy config still yields the default layout + flips the flag.
        var cfg = { powerButtonOrder: [], powerButtonsHidden: [] }
        Migrations.migrateHeaderActions(cfg)
        verify(cfg.headerActions.length > 0)
        verify(cfg.headerActionsMigrated)
    }

    // --- migrateLauncherIcon ---

    function test_launcherIconAlreadyMigratedIsNoop() {
        var cfg = {
            iconMigratedFrom17: true,
            icon: "dev.xarbit.appgrid",
            favoriteApps: ["x"]
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "dev.xarbit.appgrid")
        verify(cfg.iconMigratedFrom17)
    }

    function test_launcherIconFreshInstallKeepsNewDefault() {
        // No prior state — user is fresh, let them see the new icon.
        var cfg = {
            icon: "dev.xarbit.appgrid",
            favoriteApps: []
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "dev.xarbit.appgrid")
        verify(cfg.iconMigratedFrom17)
    }

    function test_launcherIconUpgradeFlipsToLegacyDefault() {
        // Prior state (favourites) present, icon still at the new default → user
        // never picked one, so pin them to the old default.
        var cfg = {
            icon: "dev.xarbit.appgrid",
            favoriteApps: ["firefox.desktop"]
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "start-here-kde-symbolic")
        verify(cfg.iconMigratedFrom17)
    }

    function test_launcherIconLeavesCustomImageAlone() {
        var cfg = {
            icon: "dev.xarbit.appgrid",
            useCustomButtonImage: true,
            favoriteApps: ["firefox.desktop"]
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "dev.xarbit.appgrid")
        verify(cfg.iconMigratedFrom17)
    }

    function test_launcherIconLeavesUserPickAlone() {
        // Prior state, icon is something else — user picked it, don't touch.
        var cfg = {
            icon: "applications-other",
            favoriteApps: ["firefox.desktop"]
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "applications-other")
        verify(cfg.iconMigratedFrom17)
    }

    function test_launcherIconIgnoresLaunchStateWithoutFavorites() {
        // Launch state (hidden/known/counts) moved to the shared store, so it is
        // no longer a prior-state signal: without favourites the new default stays.
        var cfg = {
            icon: "dev.xarbit.appgrid",
            launchCounts: ["firefox=3"], knownApps: ["firefox.desktop"]
        }
        Migrations.migrateLauncherIcon(cfg)
        compare(cfg.icon, "dev.xarbit.appgrid")
        verify(cfg.iconMigratedFrom17)
    }
}
