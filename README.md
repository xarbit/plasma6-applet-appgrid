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

- **Fullscreen app grid** — All installed applications in a clean, visual grid with Wayland layer-shell support
- **Category filtering** — Filter apps by category (Development, Graphics, Internet, Multimedia, Office, System, Utilities)
- **Search with KRunner integration** — Instant search with numbered results and Alt+1–9 shortcuts for quick launching
- **Quick commands** — Type `?` for help: open terminal (`t:`), run shell commands (`:`), browse files (`/`, `~/`)
- **Configurable icon size** — Small, medium, or large icons
- **Sort by most used** — Option to sort apps by launch frequency instead of alphabetically
- **New app detection** — Highlights recently installed applications with a badge
- **Session management** — Sleep, restart, shut down, lock, and log out buttons
- **Context menu** — Pin to Task Manager, Add to Desktop, Edit Application, Hide apps
- **Background customization** — Blur, opacity, and corner radius settings
- **Theme support** — Follows the user's Plasma theme (light/dark)
- **29 language translations** — European language support included
- **Show Alternatives** — Works as a drop-in replacement via Plasma's launcher alternative mechanism

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

## License

GPL-2.0-or-later
