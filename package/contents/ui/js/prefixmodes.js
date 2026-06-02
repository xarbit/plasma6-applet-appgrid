/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Single source of truth for search-bar prefix modes: the mode identifiers,
    their trigger prefixes, and the pure classification logic. PrefixDetector
    wraps this; the prefix views compare against these constants instead of
    re-typing the mode strings.
*/

.pragma library

var TERMINAL = "terminal"
var COMMAND  = "command"
var FILES    = "files"
var INFO     = "info"
var HIDDEN   = "hidden"
var HELP     = "help"
var NONE     = ""

// Classify raw search input into one of the mode constants above (or NONE).
function modeFor(input) {
    if (input.startsWith("t:")) return TERMINAL
    if (input.startsWith("i:")) return INFO
    if (input.startsWith("h:")) return HIDDEN
    if (input.startsWith("?"))  return HELP
    if (input.startsWith("/") || input.startsWith("~/")) return FILES
    if (input.startsWith(":"))  return COMMAND
    return NONE
}

// Strip the trigger prefix and return the trimmed argument for the modes that
// carry one (terminal/command/files); the rest have no argument.
function argumentFor(input, mode) {
    if (mode === TERMINAL) return input.substring(2).trim()
    if (mode === COMMAND)  return input.substring(1).trim()
    if (mode === FILES)    return input.trim()
    return ""
}
