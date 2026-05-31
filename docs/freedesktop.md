<!--
SPDX-FileCopyrightText: 2026 AppGrid Contributors
SPDX-License-Identifier: GPL-2.0-or-later
-->

# freedesktop / XDG compliance

What AppGrid reads, writes, and intentionally ignores from the
freedesktop / XDG specs. Reflects the code in `src/appmodel.cpp`,
`src/appfiltermodel.cpp`, `src/categorymapping.cpp`, and
`src/appgridplugin.cpp`.

## Followed

| Spec | How |
|------|-----|
| [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/) | Reads `.desktop` files via `KSycoca` / `KService`. Honors `Name`, `Exec`, `Icon`, `Comment`, `GenericName`, `Keywords`, `Categories`, `Actions`, `OnlyShowIn` / `NotShowIn`, `NoDisplay`, `Hidden`, `TryExec`. No custom keys. Translations are pulled from the matching `Name[lang]` / `Comment[lang]` entries. |
| `.desktop` **Actions** (jumplist) | Surfaced in the right-click context menu. Each action is launched via `KIO::ApplicationLauncherJob`. |
| [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) | Config lives in Plasma's standard `$XDG_CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc`. Icon cache, recent-apps, launch-counts: all under Plasma's per-user state. No bespoke paths. |
| [AppStream](https://specifications.freedesktop.org/appstream-spec/latest/) | "Manage in Discover" opens `appstream://<component-id>`. The component id is resolved from the `.desktop` file via `AppStream::Pool`. |
| `mimeapps.list` defaults | The grid's *Default app* tier-promotion (browser, mail, etc.) reads `~/.config/mimeapps.list` + system `mimeapps.list` to identify each mime's chosen default, then nudges those apps up within the same relevance tier. |

## Intentionally not surfaced

| Thing | Why |
|------|-----|
| [XDG Menu](https://specifications.freedesktop.org/menu-spec/latest/) tree (`<Include>` / `<Exclude>` hierarchy from `.menu` files) | AppGrid walks `KServiceGroup::root()` to enumerate apps (the spec-standard way to discover them), reads the `Categories=` field of each `.desktop` and presents categories as flat filter tags — the menu hierarchy itself is not surfaced as navigation. In system-categories mode (Settings → General), the top-level group captions become the flat category list; the deeper levels still aren't rendered. XDG Menu adoption as navigation is optional in the spec; users who want the tree view have Kicker / the classic K-menu. |
| Per-app `MimeType=` association management | Not a launcher's responsibility — left to `xdg-mime` / the system's mime-handler picker. AppGrid only *reads* defaults, never writes them. |
| Custom `.desktop` fields | None. Anything AppGrid needs to know about an app is either in the standard fields or in AppGrid's own config — keeps `.desktop` files portable to every other launcher. |

## Layered on top

| Behavior | What it does | Why it's not a spec violation |
|------|------|------|
| **Hide Application** | Records the app's storage id in AppGrid's own `hiddenApps` config. Does **not** write `NoDisplay=true` to the `.desktop` file. | System-wide `NoDisplay` would also hide the app from Kickoff, KRunner, Activities — overriding the user's choice everywhere. AppGrid's hide is launcher-local on purpose. The .desktop file stays untouched. |
| **Launch broadcast** | Every launch is reported to KActivities via `KActivities::ResourceInstance::notifyAccessed` with the URL `applications:<storage-id>` and the agent `dev.xarbit.appgrid`. | KActivities convention; the `applications:` scheme is the standard URI for desktop-file resources. AppGrid is a *contributing* launcher — Kickoff / KRunner count our launches in their own frecency views, and we read frecency back for the opt-in search-time ranking bias (see [search-pipeline.md](search-pipeline.md)). |
| **Category source — two modes** | **Simple mode (default)**: `src/categorymapping.cpp` maps the freedesktop main-category set (`Development`, `Multimedia`, `AudioVideo`, …) to a curated set of user-friendly group names. **System mode (opt-in via Settings → General → "Use KDE menu categories")**: top-level `KServiceGroup` captions become the category list — i.e. whatever the user has configured in `kmenuedit` (or whatever their distro ships). | The underlying `Categories=` value on every `.desktop` is preserved as-is via the category role; only the *grouping for the category bar* differs between modes. |

## Practical implications

- An app you hide in AppGrid still appears in Kickoff / KRunner. To hide it everywhere, set `NoDisplay=true` in its `.desktop` file (or use `kmenuedit`).
- Apps with `NoDisplay=true` or `Hidden=true` are filtered out by KService before AppGrid sees them.
- An app you pin to the panel Task Manager / drag to the Desktop goes through Plasma's `Kicker::ContainmentInterface::addLauncher` — same SPI Kickoff uses; the dropped item is a `.desktop` reference, not a copy.
- The category list comes from the union of every visible app's `Categories=` field. Distros that ship apps without `Categories=` will see them in *Other*.

## What would break the spec (and we don't)

- Writing private keys into `.desktop` files.
- Persisting user state inside `.desktop` files instead of AppGrid's config.
- Treating `Categories=` as a single value (it's a semicolon-separated set).
- Ignoring `OnlyShowIn` / `NotShowIn` (other DE's apps would leak in).

None of these are done.
