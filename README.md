# AppGrid

A modern application launcher for KDE Plasma, inspired by macOS Launchpad, COSMIC, and Pantheon.

![KDE Plasma](https://img.shields.io/badge/KDE_Plasma-6.0+-blue)
![License](https://img.shields.io/badge/License-GPL--2.0--or--later-green)

![AppGrid](images/launcher.png)

## Why AppGrid?

KDE Plasma ships with Kickoff and Kicker as its default application launchers. While they are feature-rich, I find them difficult to navigate and slower to use for everyday app launching. I've always preferred the simplicity of how COSMIC, macOS Launchpad, and Pantheon handle application launching — a clean, fullscreen grid where everything is visible at a glance. Since nothing like that existed for Plasma, I decided to build one that fits my workflow.

## Screenshots

![App Grid](images/launcher-main.png)

![Search](images/search.png)

![Quick Commands](images/quick-commands.png)

![Settings](images/settings.png)

## Features

- Category filtering and KRunner search integration
- Quick commands — terminal, shell commands, file browser (type `?` for help)
- Sort by most used or alphabetically
- New app detection with badge
- Session management (sleep, restart, shut down, lock, log out)
- Context menu with pin to Task Manager, add to Desktop, hide apps
- Customizable grid size, icon size, background blur, opacity, and corner radius
- Drop-in replacement via Plasma's Show Alternatives

## Dependencies

### Runtime
- plasma-workspace
- kservice
- ki18n
- kio

### Build
- cmake
- extra-cmake-modules
- qt6-base
- qt6-declarative
- libplasma
- kpackage
- kio

## Building

### Arch Linux (recommended)

```bash
makepkg -si
```

### Manual

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j$(nproc)
sudo cmake --install build
```

After installing, restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

## Usage

1. Right-click your current application launcher in the panel
2. Select **Show Alternatives**
3. Choose **AppGrid**

Or add it as a new widget: right-click the panel → **Add Widgets** → search for **AppGrid**.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| Super | Toggle AppGrid |
| Escape | Close |
| Enter | Launch top search result |
| Alt+1–9 | Launch numbered search result |
| Arrow keys | Navigate results |
| Tab | Cycle categories |
| Type anywhere | Start searching |

## Configuration

Right-click the AppGrid panel icon → **Configure AppGrid** → **General**.

![Settings](images/settings.png)

| Setting | Description | Default |
|---------|-------------|---------|
| **Icon** | Panel icon or custom image | `start-here-kde-symbolic` |
| **Display mode** | **Fullscreen overlay** covers the entire screen with a blurred background, similar to macOS Launchpad. **Centered popup** opens a floating window in the center of the screen that dismisses when clicking outside or losing focus. *This setting is temporary for testing both implementations — one will be chosen as the default in a future release.* | Centered popup |
| **Icons per row** | Number of columns in the grid | 7 |
| **Visible rows** | Number of rows visible before scrolling | 4 |
| **Icon size** | Small, medium, or large | Large |
| **Sort order** | **Alphabetical** sorts apps A–Z. **Most Used** sorts by launch frequency, so your most opened apps appear first. | Most Used |
| **Show scrollbars** | Show scrollbars in grid and search views | Off |
| **Enable background blur** | Blur effect behind the launcher | On |
| **Shake icons on open** | Subtle icon animation when launcher opens | On |
| **Show labels on power/session buttons** | Text labels on sleep, restart, shut down, etc. | Off |
| **Expand search to bookmarks, files, and websites** | Use additional KRunner plugins for search | On |
| **Background opacity** | Opacity of the launcher background (0–100%) | 85% |
| **Corner radius** | Override the default corner radius (in pixels) | 24 px (off by default) |
| **Hidden Applications** | Apps hidden from the grid via right-click → Hide | — |

## Credits

- **Jason Scurtu** — Author
- **[@claude](https://github.com/claude)** — AI pair programming assistant

Disclaimer:
This project uses [Claude Code](https://claude.ai/claude-code) as an AI pair programmer and AI assistant. To be clear: this is **not** vibe-coded — it is context engineered and reviewed. Nevertheless, if AI-assisted code gives you the ick, this might not be the launcher for you.

## License

GPL-2.0-or-later
