/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "menutree.h"

/**
 * @brief Builds a MenuTree from the live KServiceGroup hierarchy (issue #201).
 *
 * The thin KSycoca-facing half of the menu tree: walks KServiceGroup::root(),
 * emits the flat RawFolder / RawApp the pure assembler consumes, and returns the
 * assembled tree. Kept apart from MenuTree (pure, unit-tested) and MenuTreeModel
 * (navigation) so the only KSycoca dependency lives in one small place.
 */
namespace MenuTreeSource
{

/** Walk the system application menu into a MenuTree. Honours the same
 *  no-display / non-application filtering AppModel applies. */
[[nodiscard]] MenuTree::Node fromKServiceGroup();

} // namespace MenuTreeSource
