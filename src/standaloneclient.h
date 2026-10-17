/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

/**
 * How a plasmoid reaches the standalone `appgrid` daemon: call a method on the
 * running instance, or start it with the matching command-line flags. A
 * running daemon left over from an upgrade (a different build, missing our
 * methods) is asked to quit and replaced by ours.
 */
class StandaloneClient
{
public:
    /** Call @p dbusMethod with @p dbusArgs on the running daemon, or start it
     *  with @p launchArgs. */
    void trigger(const QString &dbusMethod, const QStringList &launchArgs, const QVariantList &dbusArgs = {});
    /** trigger() on behalf of the plasmoid @p plasmoidId, so the daemon knows
     *  which plasmoid owns the launcher session or settings it opens (#191). */
    void triggerAsOwner(const QString &plasmoidId, const QString &dbusMethod, const QStringList &extraFlags = {});

    /** The launch flags for triggerAsOwner(): @p extraFlags and the owner's id. */
    [[nodiscard]] static QStringList ownerLaunchArgs(const QString &plasmoidId, const QStringList &extraFlags);

private:
    // Cached result of the running daemon's version probe.
    bool m_versionChecked = false;
    bool m_stale = false;
};
