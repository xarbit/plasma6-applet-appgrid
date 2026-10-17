/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "applauncher.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenUrlJob>

#include <QDebug>
#include <QUrl>

namespace
{
void start(KJob *job)
{
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    QObject::connect(job, &KJob::finished, job, [](KJob *finished) {
        if (finished->error()) {
            qWarning() << "AppGrid: launch failed:" << finished->errorString();
        }
    });
    job->start();
}
}

namespace AppLauncher
{
bool launch(const KService::Ptr &service)
{
    if (!service) {
        return false;
    }
    start(new KIO::ApplicationLauncherJob(service));
    return true;
}

void launch(const KServiceAction &action)
{
    start(new KIO::ApplicationLauncherJob(action));
}

void open(const QUrl &url)
{
    start(new KIO::OpenUrlJob(url));
}
}
