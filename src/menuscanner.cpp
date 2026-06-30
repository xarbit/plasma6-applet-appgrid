/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "menuscanner.h"

#include <KService>
#include <KServiceGroup>

#include <QString>

#include <functional>

namespace MenuScanner
{

RawScan scan(bool systemMode)
{
    RawScan out;

    // Recurse the XDG menu. Two contexts thread down the tree:
    //   topCategory — the first-level group's caption, the system-mode category
    //                 every descendant app inherits (set once, never overwritten).
    //   relPath     — the current folder's menu path, the folder an app sits in.
    std::function<void(const KServiceGroup::Ptr &, const QString &, const QString &)> walk;
    walk = [&](const KServiceGroup::Ptr &group, const QString &topCategory, const QString &relPath) {
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
                const QString caption = subGroup->caption().isEmpty() ? subGroup->name() : subGroup->caption();

                // Emit the folder for the tree (every level).
                MenuTree::RawFolder folder;
                folder.relPath = subGroup->relPath();
                folder.name = caption;
                folder.icon = subGroup->icon();
                out.folders.append(folder);

                // The top-level caption is the category descendants inherit; once
                // set (we're below the root) it sticks for the whole subtree.
                const QString childTop = topCategory.isEmpty() ? caption : topCategory;
                walk(subGroup, childTop, subGroup->relPath());
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

            AppEntry appEntry;
            appEntry.name = service->name();
            appEntry.icon = service->icon();
            appEntry.desktopFile = service->entryPath();
            appEntry.genericName = service->genericName();
            appEntry.storageId = storageId;
            appEntry.keywords = service->keywords();
            appEntry.comment = service->comment();
            // entryPath() is the resolved absolute .desktop path (KService applies
            // XDG precedence), so no extra stat is needed to detect the source.
            appEntry.installSource = AppModel::detectInstallSource(service->exec(), service->entryPath());
            appEntry.folderRelPath = relPath;
            if (systemMode) {
                appEntry.categories.append(topCategory.isEmpty() ? QStringLiteral("Other") : topCategory);
            } else {
                appEntry.categories = AppModel::mapCategories(service->categories());
            }
            out.occurrences.append(appEntry);
        }
    };

    walk(KServiceGroup::root(), QString(), QString());
    return out;
}

} // namespace MenuScanner
