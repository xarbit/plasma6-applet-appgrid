/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "menutreesource.h"

#include <KService>
#include <KServiceGroup>

#include <QList>

#include <functional>

namespace MenuTreeSource
{

MenuTree::Node fromKServiceGroup()
{
    QList<MenuTree::RawFolder> folders;
    QList<MenuTree::RawApp> apps;

    // Recurse the menu, emitting one RawFolder per subgroup and one RawApp per
    // app occurrence under the group it was reached through. The pure assembler
    // (MenuTree::build) nests them, so the structure rules live in one tested
    // place. Mirrors AppModel's walk (no-display / non-application filtering).
    std::function<void(const KServiceGroup::Ptr &, const QString &)> walk;
    walk = [&](const KServiceGroup::Ptr &group, const QString &relPath) {
        if (!group || !group->isValid()) {
            return;
        }
        const auto entries = group->entries(true /* sorted */, true /* excludeNoDisplay */, false /* allowSeparators */, true /* sortByGenericName */);
        for (const auto &entry : entries) {
            if (entry->isType(KST_KServiceGroup)) {
                const auto subGroup = KServiceGroup::Ptr(static_cast<KServiceGroup *>(entry.data()));
                if (!subGroup || !subGroup->isValid() || subGroup->noDisplay()) {
                    continue;
                }
                MenuTree::RawFolder folder;
                folder.relPath = subGroup->relPath();
                folder.name = subGroup->caption().isEmpty() ? subGroup->name() : subGroup->caption();
                folder.icon = subGroup->icon();
                folders.append(folder);
                walk(subGroup, subGroup->relPath());
                continue;
            }

            if (!entry->isType(KST_KService)) {
                continue;
            }
            const auto service = KService::Ptr(static_cast<KService *>(entry.data()));
            if (!service->isApplication() || service->noDisplay() || service->exec().isEmpty()) {
                continue;
            }
            const QString storageId = service->storageId();
            if (storageId.isEmpty()) {
                continue;
            }
            MenuTree::RawApp app;
            app.folderRelPath = relPath;
            app.leaf = MenuTree::AppLeaf{storageId, service->name(), service->icon()};
            apps.append(app);
        }
    };

    walk(KServiceGroup::root(), QString());
    return MenuTree::build(folders, apps);
}

} // namespace MenuTreeSource
