/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "standaloneoptions.h"

#include "appgridconstants.h"

StandaloneOptions StandaloneOptions::parse(const QStringList &arguments)
{
    using namespace AppGrid::Standalone;
    StandaloneOptions options;
    options.daemon = arguments.contains(FlagDaemon);
    options.configure = arguments.contains(FlagConfigure);
    options.compact = arguments.contains(FlagCompact);
    options.replace = arguments.contains(FlagReplace);
    for (const QString &argument : arguments) {
        if (argument.startsWith(FlagPlasmoidId)) {
            options.plasmoidId = argument.mid(FlagPlasmoidId.size());
            break;
        }
    }
    return options;
}
