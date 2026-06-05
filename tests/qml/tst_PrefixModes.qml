/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for prefixmodes.js — the search-bar prefix classifier and its
    argument extractor. The triggers (t:/i:/h:/?///~//:) are user-facing and
    the prefix views compare against these mode constants, so the mapping and
    the per-mode argument trimming are pinned here.
*/

import QtQuick
import QtTest
import "prefixmodes.js" as PrefixModes

TestCase {
    name: "PrefixModes"

    // --- modeFor: each trigger maps to its mode ---

    function test_modeForTerminal() {
        compare(PrefixModes.modeFor("t:htop"), PrefixModes.TERMINAL)
    }

    function test_modeForInfo() {
        compare(PrefixModes.modeFor("i:kate"), PrefixModes.INFO)
    }

    function test_modeForHidden() {
        compare(PrefixModes.modeFor("h:daemon"), PrefixModes.HIDDEN)
    }

    function test_modeForHelp() {
        compare(PrefixModes.modeFor("?"), PrefixModes.HELP)
        compare(PrefixModes.modeFor("?anything"), PrefixModes.HELP)
    }

    function test_modeForFilesAbsolute() {
        compare(PrefixModes.modeFor("/usr/bin"), PrefixModes.FILES)
    }

    function test_modeForFilesHome() {
        compare(PrefixModes.modeFor("~/Documents"), PrefixModes.FILES)
    }

    function test_modeForCommand() {
        compare(PrefixModes.modeFor(":reboot"), PrefixModes.COMMAND)
    }

    function test_modeForNoneOnPlainText() {
        compare(PrefixModes.modeFor("firefox"), PrefixModes.NONE)
    }

    function test_modeForNoneOnEmpty() {
        compare(PrefixModes.modeFor(""), PrefixModes.NONE)
    }

    // A bare "~" without the slash is not a files trigger.
    function test_modeForTildeWithoutSlashIsNone() {
        compare(PrefixModes.modeFor("~user"), PrefixModes.NONE)
    }

    // Help only triggers on a leading '?'; embedded '?' classifies as plain.
    function test_modeForEmbeddedQuestionMarkIsNone() {
        compare(PrefixModes.modeFor("foo?bar"), PrefixModes.NONE)
    }

    // Bare "/" opens the file browser at the filesystem root.
    function test_modeForFilesRootPath() {
        compare(PrefixModes.modeFor("/"), PrefixModes.FILES)
    }

    // --- argumentFor: strip the trigger, trim, only for arg-carrying modes ---

    function test_argumentForTerminalStripsAndTrims() {
        compare(PrefixModes.argumentFor("t:  htop ", PrefixModes.TERMINAL), "htop")
    }

    function test_argumentForCommandStripsAndTrims() {
        compare(PrefixModes.argumentFor(":  reboot ", PrefixModes.COMMAND), "reboot")
    }

    // Files keeps the leading path (the "/" is part of the argument, not a
    // strippable prefix); only surrounding whitespace is trimmed.
    function test_argumentForFilesKeepsPath() {
        compare(PrefixModes.argumentFor(" /usr/bin ", PrefixModes.FILES), "/usr/bin")
    }

    function test_argumentForArgumentlessModesEmpty() {
        compare(PrefixModes.argumentFor("?help", PrefixModes.HELP), "")
        compare(PrefixModes.argumentFor("i:kate", PrefixModes.INFO), "")
        compare(PrefixModes.argumentFor("h:x", PrefixModes.HIDDEN), "")
        compare(PrefixModes.argumentFor("plain", PrefixModes.NONE), "")
    }

    function test_argumentForEmptyAfterTrigger() {
        compare(PrefixModes.argumentFor("t:", PrefixModes.TERMINAL), "")
        compare(PrefixModes.argumentFor(":", PrefixModes.COMMAND), "")
    }

    // Everything after the trigger is preserved verbatim (only trimmed): a
    // pipe / embedded '?' in a command, or an embedded ':' in a file path,
    // must not re-classify or get mangled.
    function test_argumentForCommandKeepsPipes() {
        compare(PrefixModes.argumentFor(":ls -la | grep x", PrefixModes.COMMAND),
                "ls -la | grep x")
    }

    function test_argumentForCommandKeepsEmbeddedQuestionMark() {
        compare(PrefixModes.argumentFor(":echo what?", PrefixModes.COMMAND), "echo what?")
    }

    function test_argumentForFilesKeepsEmbeddedColon() {
        compare(PrefixModes.argumentFor("/tmp/foo:bar", PrefixModes.FILES), "/tmp/foo:bar")
    }
}
