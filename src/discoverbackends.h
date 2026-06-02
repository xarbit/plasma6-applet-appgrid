/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>

/**
 * Plasma-free mapping between AppModel install-source strings, Discover
 * backend plugin names, and the runtime dependency that gates each backend.
 * Extracted from AppGridPlugin so the install-source ↔ backend protocol (a
 * typo here silently breaks the "Manage in Discover" gate) is a single
 * source of truth and unit-testable.
 */
namespace DiscoverBackends
{
/** Discover backend plugin name that manages a given AppModel install-source
 *  ("System" → packagekit, "Flatpak" → flatpak, "Snap" → snap); empty for
 *  sources Discover doesn't manage. */
[[nodiscard]] QString forInstallSource(const QString &source);

/** CLI whose presence gates the backend (flatpak / snap). Empty for
 *  packagekit, which is reached over a D-Bus-activated system service
 *  instead — see isBackendInstalled(). */
[[nodiscard]] QString toolForBackend(const QString &backend);

/** True when the Discover backend plugin (.so) is present and its runtime
 *  dependency is satisfied (Flatpak/Snap CLI, or the PackageKit D-Bus
 *  service). Touches the filesystem; cheap enough to call per right-click. */
[[nodiscard]] bool isBackendInstalled(const QString &name);
}
