/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "menutreesource.h"

namespace MenuTreeSource
{

MenuTree::Node fromScan(const QList<MenuTree::RawFolder> &folders, const QVector<AppEntry> &occurrences)
{
    // Project each app occurrence onto the tree's RawApp shape (the folder it
    // sits in + its leaf). The scanner already filtered no-display / non-app
    // services, so this is a straight map.
    QList<MenuTree::RawApp> apps;
    apps.reserve(occurrences.size());
    for (const auto &occurrence : occurrences) {
        apps.append(MenuTree::RawApp{occurrence.folderRelPath, MenuTree::AppLeaf{occurrence.storageId, occurrence.name, occurrence.icon}});
    }
    return MenuTree::build(folders, apps);
}

} // namespace MenuTreeSource
