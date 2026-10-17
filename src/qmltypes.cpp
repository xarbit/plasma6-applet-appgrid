/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "qmltypes.h"

#include "abstractgroupedmodel.h"
#include "appfiltermodel.h"
#include "hiddenappsmodel.h"

#include <QQmlEngine>

#include <mutex>

void AppGridQml::registerTypes()
{
    static std::once_flag once;
    std::call_once(once, [] {
        const char *uri = "dev.xarbit.appgrid.models";
        const QString reason = QStringLiteral("Owned by the launcher controller");
        qmlRegisterUncreatableType<AppFilterModel>(uri, 1, 0, "AppFilterModel", reason);
        qmlRegisterUncreatableType<AbstractGroupedModel>(uri, 1, 0, "AbstractGroupedModel", reason);
        qmlRegisterType<HiddenAppsModel>(uri, 1, 0, "HiddenAppsModel");
    });
}
