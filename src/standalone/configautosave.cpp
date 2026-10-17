/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "configautosave.h"

#include <KCoreConfigSkeleton>

#include <QCoreApplication>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QTimer>

namespace ConfigAutosave
{
void install(KCoreConfigSkeleton *config, int debounceMs)
{
    auto *saveTimer = new QTimer(config);
    saveTimer->setSingleShot(true);
    saveTimer->setInterval(debounceMs);
    QObject::connect(saveTimer, &QTimer::timeout, config, [config]() {
        config->save();
    });
    const QMetaObject *meta = config->metaObject();
    const QMetaMethod start = saveTimer->metaObject()->method(saveTimer->metaObject()->indexOfMethod("start()"));
    for (int i = meta->propertyOffset(); i < meta->propertyCount(); ++i) {
        const QMetaProperty property = meta->property(i);
        if (property.hasNotifySignal()) {
            QObject::connect(config, property.notifySignal(), saveTimer, start);
        }
    }
    QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, config, [config]() {
        config->save();
    });
}
}
