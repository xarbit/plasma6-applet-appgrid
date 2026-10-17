/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "appfieldscache.h"

#include "appresolver.h"
#include "installsource.h"

AppFieldsCache::Fields AppFieldsCache::fields(const QString &id) const
{
    const auto cached = m_fields.constFind(id);
    if (cached != m_fields.constEnd()) {
        return *cached;
    }
    const AppResolver::Target target = AppResolver::resolve(id);
    Fields fields;
    fields.name = target.name;
    fields.icon = target.icon;
    if (target.service) {
        fields.genericName = target.service->genericName();
        fields.comment = target.service->comment();
        fields.desktopFile = target.service->entryPath();
        fields.installSource = InstallSource::of(target.service);
    }
    return *m_fields.insert(id, fields);
}

void AppFieldsCache::clear()
{
    m_fields.clear();
}
