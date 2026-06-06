# Optional: auto-restart Plasma after an AppGrid update

AppGrid is a compiled Plasma applet — a C++ plugin (`.so`) loaded into the
running `plasmashell`. When a package update replaces it under a live session,
Plasma cannot hot-swap the binary, so the shell keeps the stale plugin (and can
freeze) until it is restarted. The fix is always the same: restart Plasma once,
in your own session:

```sh
systemctl --user restart plasma-plasmashell.service   # Wayland / systemd session
kquitapp6 plasmashell && kstart plasmashell            # X11
```

The packages only **print** this reminder — a package script runs as root with
no access to your session, so it cannot (and should not) restart your shell for
you, and doing so unprompted would drop whatever you have open.

If you want that restart to happen **automatically on your own machine**, these
opt-in systemd *user* units do it safely: they run as you, in your session, and
trigger only when the AppGrid `.so` actually changes.

> [!WARNING]
> Restarting `plasmashell` closes open menus and resets plasmoid transient
> state. That is fine for a deliberate, personal choice — which is exactly why
> this is opt-in and not shipped enabled.

## Install

```sh
mkdir -p ~/.config/systemd/user
cp appgrid-restart-plasma.path appgrid-restart-plasma.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now appgrid-restart-plasma.path
```

## Disable / remove

```sh
systemctl --user disable --now appgrid-restart-plasma.path
rm ~/.config/systemd/user/appgrid-restart-plasma.{path,service}
systemctl --user daemon-reload
```

## Notes

- The `.path` unit watches both install locations (`~/.local` and `/usr`) and
  both variants; non-existent paths are ignored, so it works regardless of how
  you installed.
- `ExecStart` uses `systemctl --user restart plasma-plasmashell.service`, the
  systemd-managed session shell on Plasma 6 (Wayland and X11). On a session that
  doesn't manage `plasmashell` via systemd the restart is a harmless no-op; use
  the `kquitapp6 && kstart` form manually there.
- Prefer not to add units? A shell wrapper does the same per-update, e.g.
  `yay -Syu && systemctl --user restart plasma-plasmashell.service`.
