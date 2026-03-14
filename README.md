# AppGrid

A modern fullscreen application launcher for KDE Plasma, inspired by macOS Launchpad and COSMIC.

![KDE Plasma](https://img.shields.io/badge/KDE_Plasma-6.0+-blue)
![License](https://img.shields.io/badge/License-GPL--2.0--or--later-green)

![AppGrid](images/launcher.png)

## Screenshots

![App Grid](images/launcher-main.png)

![Search](images/search.png)

![Quick Commands](images/quick-commands.png)

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

Right-click the AppGrid panel icon → **Configure AppGrid** → **General**:

- **Panel icon** — Choose a custom icon or drag-and-drop an image file
- **Icon size** — Small, medium, or large grid icons
- **Grid dimensions** — Columns and rows
- **Sort order** — Alphabetical or most used
- **Background** — Blur, opacity, and corner radius

## License

GPL-2.0-or-later
