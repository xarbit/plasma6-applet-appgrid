<p align="center">
  <img src="images/appgrid-logo.svg" alt="AppGrid" width="128" />
</p>

<h1 align="center">AppGrid — KDE Plasma 6 Application Launcher</h1>

A grid-style application launcher for KDE Plasma 6. Ships as two plasmoids — a standalone centered popup (**AppGrid**) and a native Plasma panel popup (**AppGrid Panel**) — both sharing the same grid, search, categories, and config.

![KDE Plasma](https://img.shields.io/badge/KDE_Plasma-6.0+-blue) ![License](https://img.shields.io/badge/License-GPL--2.0--or--later-green)

![AppGrid](images/launcher-main.png)

![AppGrid Dark](images/launcher-main-dark.png)

- **[appgrid.xarbit.dev](https://appgrid.xarbit.dev)** for screenshots, features, FAQ, install instructions, etc.
- **[appgrid.xarbit.dev/docs/](https://appgrid.xarbit.dev/docs/)** for build instructions, configuration reference, internals, etc.

---

## Install

Built, signed, and published by the AppGrid maintainer. These are the channels safe to recommend by default.

| Distro | Command |
|---|---|
| **Arch Linux + derivatives** (AUR) | `yay -S plasma6-applets-appgrid` |
| **Ubuntu 25.10+** (Launchpad PPA) | `sudo add-apt-repository ppa:xarbit/plasma-applet-appgrid && sudo apt install plasma-applet-appgrid` |
| **Fedora** (Copr) | `sudo dnf copr enable scujas/plasma-applet-appgrid && sudo dnf install plasma-applet-appgrid` |
| **Immutable distros** (KDE Linux, Kinoite, Bazzite, Aurora, Kalpa, SteamOS) | Universal `~/.local/` tarball — see [INSTALL.TXT](packaging/universal/INSTALL.TXT) |
| **Nix / NixOS** | Flake — see [packaging/nix/README.md](packaging/nix/README.md) |

After install: right-click the panel launcher → **Show Alternatives** → **AppGrid**.

Full per-distro guide with download links, checksums, and step-by-step terminal commands: **[appgrid.xarbit.dev/#install](https://appgrid.xarbit.dev/#install)**.

### Community packages

Maintained by third-party contributors, **not** by the AppGrid project. They are listed here as a convenience for users of those distros; we do not build, sign, audit, or vet the packages and cannot vouch for what each maintainer ships. Please open issues against the linked overlay/package, not this repo.

| Distro | Source | Maintainer |
|---|---|---|
| **openSUSE** | [OBS package](https://build.opensuse.org/package/show/home:JMarcosHP01/plasma6-applet-appgrid) | [@JMarcosHP01](https://github.com/JMarcosHP01) |
| **Gentoo** | [Overlay](https://github.com/mnalmahmud/mnalmahmud-overlay) | [@mnalmahmud](https://github.com/mnalmahmud) |
| **Fedora** (Terra) | [Terra package](https://github.com/terrapkg/packages/blob/frawhide/anda/desktops/kde/plasma6-applet-appgrid/plasma6-applet-appgrid.spec) | [@hilltty](https://github.com/hilltty) |

If you maintain an AppGrid package for a distro not listed here, open an issue and we will add you.

> [!CAUTION]
> **Impersonation caution.** A repository at `github.com/RishiT07-op/plasma6-applet-appgrid` is impersonating this project (not a fork, ships an unknown `.zip`, issues disabled). Only install from the official sources. Details + status: [#115](https://github.com/xarbit/plasma6-applet-appgrid/issues/115).

### Build from source

Requires Plasma 6.0+ (6.4+ recommended) and the KDE Frameworks 6 development headers — see [`PKGBUILD`](PKGBUILD) for the Arch list, or [`packaging/`](packaging/) for the Fedora spec and Ubuntu `debian/` packaging.

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j$(nproc)
sudo cmake --install build
kquitapp6 plasmashell && kstart plasmashell
```

Arch users can build a proper pacman package with `makepkg -sf` and install via `sudo pacman -U plasma6-applets-appgrid-*.pkg.tar.zst`.

---

## Documentation

Full docs live on the website: **[appgrid.xarbit.dev/docs](https://appgrid.xarbit.dev/docs/)**.

- **[Build from source](https://appgrid.xarbit.dev/docs/#build-from-source)** + **[Dependencies (per distro)](https://appgrid.xarbit.dev/docs/#dependencies-per-distro)** + **[CMake build options](https://appgrid.xarbit.dev/docs/#cmake-build-options)**
- **[Configuration reference](https://appgrid.xarbit.dev/docs/#configuration-reference)** — every setting with default + effect
- **[Plasmoid variants & IDs](https://appgrid.xarbit.dev/docs/#plasmoid-variants--ids)** · **[Favorites storage](https://appgrid.xarbit.dev/docs/#favorites-storage)** · **[Universal package internals](https://appgrid.xarbit.dev/docs/#universal-package-internals)** · **[Update checker internals](https://appgrid.xarbit.dev/docs/#update-checker--technical)** · **[Versioning scheme](https://appgrid.xarbit.dev/docs/#versioning-scheme)**
- **[State file locations](https://appgrid.xarbit.dev/docs/#state-file-locations)** · **[Running the test suite](https://appgrid.xarbit.dev/docs/#running-the-test-suite)** · **[Translations workflow](https://appgrid.xarbit.dev/docs/#translations)**
- **[Help & troubleshooting](https://appgrid.xarbit.dev/docs/#help--troubleshooting)** — 1.7.x upgrade, distro ↔ universal switching, logs / debugging, bug-reporting

---

## Contributing

- **Bugs / ideas** — [open an issue](https://github.com/xarbit/plasma6-applet-appgrid/issues) with steps to reproduce and your Plasma version (`i:` in the search bar copies your system info)
- **Translations** — `.po` files live in [`po/`](po/); add or improve a language and open a PR
- **Code** — fork, branch, PR. Keep changes focused; test against both AppGrid Center and AppGrid Panel
- **Packaging** — if you maintain AppGrid for a distro not listed above, open an issue and I'll add it

---

## Credits

- **Jason Scurtu** — author

This project is developed with [Claude Code](https://claude.com/product/claude-code) as an AI pair programmer. Context-engineered and reviewed, not vibe-coded — but if AI-assisted code gives you the ick, this might not be the launcher for you.

---

## Acknowledgments

AppGrid stands on the work of the KDE community.

**Built with KDE Frameworks 6 & Plasma** — KGlobalAccel, KRunner, KIO, KIconThemes, KCoreAddons, KWindowSystem, Plasma::Applet/PlasmaQuick, PlasmaActivities, LayerShellQt. Without these, none of this exists.

**Inspired by KDE's own launchers** — Kickoff for the popup layout conventions, Kicker for the SPI patterns we reuse (ProcessRunner, ContainmentInterface), KRunner whose results feed our search via KRunner::ResultsModel.

Thanks to the Plasma team, the Frameworks maintainers, and every contributor whose work AppGrid builds on.

---

## License

[GPL-2.0-or-later](https://spdx.org/licenses/GPL-2.0-or-later.html).
