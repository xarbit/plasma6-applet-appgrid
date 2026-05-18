# AppGrid — KDE Plasma 6 Application Launcher

> **🧪 Release candidate: `v1.8.0-rc.1`** — universal package for immutable distros, opt-in in-app update checker, by-category drag-and-drop, hardened installer. Please [report regressions](https://github.com/xarbit/plasma6-applet-appgrid/issues) before 1.8.0 stable ships. Type `i:` in the search bar to copy your system info for a report.

A grid-style application launcher for KDE Plasma 6, inspired by macOS Launchpad, COSMIC, and Pantheon. Ships as two plasmoids — a standalone centered popup (**AppGrid**) and a native Plasma panel popup (**AppGrid Panel**) — both sharing the same grid, search, categories, and config.

![KDE Plasma](https://img.shields.io/badge/KDE_Plasma-6.0+-blue)
![License](https://img.shields.io/badge/License-GPL--2.0--or--later-green)

![AppGrid](images/launcher.png)

Website with screenshots, features, FAQ, and install instructions: **[appgrid.xarbit.dev](https://appgrid.xarbit.dev)**. Build instructions, configuration reference, internals, and contributor notes: **[appgrid.xarbit.dev/docs](https://appgrid.xarbit.dev/docs)**.

## Install

| Distro | Command |
|---|---|
| **Arch Linux + derivatives** (AUR — official) | `yay -S plasma6-applets-appgrid` |
| **Fedora / Ubuntu / Debian** | Pre-built `.rpm` / `.deb` on the [Releases](https://github.com/xarbit/plasma6-applet-appgrid/releases) page |
| **Immutable distros** (KDE Linux, Kinoite, Bazzite, Aurora, Kalpa, SteamOS) | Universal `~/.local/` tarball — see [INSTALL.TXT](packages/universal/INSTALL.TXT) |
| **openSUSE** (community) | [OBS package by @JMarcosHP01](https://build.opensuse.org/package/show/home:JMarcosHP01/plasma6-applet-appgrid) |
| **Gentoo** (community) | [Overlay by @mnalmahmud](https://github.com/mnalmahmud/mnalmahmud-overlay) |

After install: right-click the panel launcher → **Show Alternatives** → **AppGrid**.

Full per-distro guide with download links, checksums, and step-by-step terminal commands: **[appgrid.xarbit.dev/#install](https://appgrid.xarbit.dev/#install)**.

## Build from source

Requires Plasma 6.0+ (6.4+ recommended) and the KDE Frameworks 6 development headers — see [`PKGBUILD`](PKGBUILD) for the Arch list or the spec files under [`packages/`](packages/) for Fedora / Debian / openSUSE equivalents.

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j$(nproc)
sudo cmake --install build
kquitapp6 plasmashell && kstart plasmashell
```

Arch users can build a proper pacman package with `makepkg -sf` and install via `sudo pacman -U plasma6-applets-appgrid-*.pkg.tar.zst`.

## Documentation

Full docs live on the website: **[appgrid.xarbit.dev/docs](https://appgrid.xarbit.dev/docs)**.

- **[Build from source](https://appgrid.xarbit.dev/docs#build-from-source)** + **[Dependencies (per distro)](https://appgrid.xarbit.dev/docs#dependencies)** + **[CMake build options](https://appgrid.xarbit.dev/docs#cmake-options)**
- **[Configuration reference](https://appgrid.xarbit.dev/docs#configuration)** — every setting with default + effect
- **[Plasmoid variants & IDs](https://appgrid.xarbit.dev/docs#plasmoid-variants)** · **[Favorites storage](https://appgrid.xarbit.dev/docs#favorites-storage)** · **[Universal package internals](https://appgrid.xarbit.dev/docs#universal-internals)** · **[Update checker internals](https://appgrid.xarbit.dev/docs#update-checker)** · **[Versioning scheme](https://appgrid.xarbit.dev/docs#versioning)**
- **[State file locations](https://appgrid.xarbit.dev/docs#state-files)** · **[Running the test suite](https://appgrid.xarbit.dev/docs#tests)** · **[Translations workflow](https://appgrid.xarbit.dev/docs#translations)**
- **[Help & troubleshooting](https://appgrid.xarbit.dev/docs#help)** — 1.7.x upgrade, distro ↔ universal switching, logs / debugging, bug-reporting

## Contributing

- **Bugs / ideas** — [open an issue](https://github.com/xarbit/plasma6-applet-appgrid/issues) with steps to reproduce and your Plasma version (`i:` in the search bar copies your system info)
- **Translations** — `.po` files live in [`po/`](po/); add or improve a language and open a PR
- **Code** — fork, branch, PR. Keep changes focused; test against both AppGrid Center and AppGrid Panel
- **Packaging** — if you maintain AppGrid for a distro not listed above, open an issue and I'll add it

## Credits

- **Jason Scurtu** — author

This project is developed with [Claude Code](https://claude.ai/claude-code) as an AI pair programmer. Context-engineered and reviewed, not vibe-coded — but if AI-assisted code gives you the ick, this might not be the launcher for you.

## License

GPL-2.0-or-later
