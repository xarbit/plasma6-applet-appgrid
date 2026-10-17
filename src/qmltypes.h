/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

/**
 * The C++ types whose enums the shared QML uses by name, under the
 * dev.xarbit.appgrid.models import (AppFilterModel.ByCategory,
 * AbstractGroupedModel.Folder, ...). Not creatable from QML: the controller
 * owns the instances.
 */
namespace AppGridQml
{
/** Register the types once per process; call before any shared QML loads. */
void registerTypes();
}
