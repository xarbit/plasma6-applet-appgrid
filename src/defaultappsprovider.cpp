/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "defaultappsprovider.h"

#include "defaultappsresolver.h"

#include <KConfigGroup>
#include <KSharedConfig>
#include <KSycoca>

#include <QElapsedTimer>
#include <QLoggingCategory>
#include <QTimer>

namespace
{
// Off by default; enable with QT_LOGGING_RULES="appgrid.perf.debug=true" to time
// the cost of resolving the default apps (#200).
Q_LOGGING_CATEGORY(lcPerf, "appgrid.perf", QtWarningMsg)
}

DefaultAppsProvider::DefaultAppsProvider(QObject *parent)
    : QObject(parent)
{
    QTimer::singleShot(0, this, &DefaultAppsProvider::reload);

    // KSycoca::databaseChanged covers app install/removal and the mimeapps
    // default set; the kdeglobals watcher covers the terminal override the KCM
    // writes there.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &DefaultAppsProvider::reload);
    m_kdeglobalsWatcher = KConfigWatcher::create(KSharedConfig::openConfig(QStringLiteral("kdeglobals")));
    connect(m_kdeglobalsWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &) {
        if (group.name() == QLatin1String("General")) {
            reload();
        }
    });
}

void DefaultAppsProvider::reload()
{
    QElapsedTimer timer;
    timer.start();
    const auto resolved = DefaultAppsResolver::resolve();
    qCDebug(lcPerf) << "default apps resolved" << resolved.defaults.size() << "defaults in" << timer.nsecsElapsed() / 1000 << "us";
    if (resolved.defaults == m_defaults && resolved.preferred == m_preferred) {
        return;
    }
    m_defaults = resolved.defaults;
    m_preferred = resolved.preferred;
    Q_EMIT changed();
}
