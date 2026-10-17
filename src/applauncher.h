/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KService>

class QUrl;

/**
 * The one place AppGrid starts an application or opens a document. Every job
 * gets KIO's default UI delegate, so KIO can ask to trust a non-executable
 * .desktop file and report a failed launch instead of failing silently (#226),
 * and every failure is logged. The jobs delete themselves.
 */
namespace AppLauncher
{
/** Start @p service. Returns false (and starts nothing) when it is null. */
bool launch(const KService::Ptr &service);

/** Start a jump-list action of an application. */
void launch(const KServiceAction &action);

/** Open @p url, a document favourite, in its preferred application. */
void open(const QUrl &url);
}
