# Nix / NixOS

AppGrid ships a standalone flake at the repository root (`flake.nix`) and the
derivation under `packaging/nix/package.nix`. Both classic Nix and flake-based
workflows are supported.

> **Note:** AppGrid is a Plasma *applet* — a `.so` plugin plus QML, not a
> standalone executable. There is no `nix run`; you install it as a package
> and then add the AppGrid widget through Plasma's *Add Widgets* dialog.

## Build / inspect

```bash
# Build into ./result
nix build github:xarbit/plasma6-applet-appgrid
ls result/lib/qt6/plugins/plasma/applets/dev.xarbit.appgrid.so   # ← the plasmoid

# Build + run the C++/QML test suite
nix flake check github:xarbit/plasma6-applet-appgrid
```

## NixOS (system-wide)

In your `configuration.nix` or flake-based system module:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.appgrid.packages.${pkgs.system}.default
  ];
}
```

With the flake declared in your inputs:

```nix
inputs.appgrid.url = "github:xarbit/plasma6-applet-appgrid";
```

After rebuild + logout/login, add **AppGrid Launcher Center** (or
**AppGrid Launcher Panel**) via Plasma's *Add Widgets* dialog.

## Home Manager

Install per-user without affecting the system:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.appgrid.packages.${pkgs.system}.default
  ];
}
```

## Overlay

The flake exposes `overlays.default`, so other flakes can pull AppGrid into
their `pkgs`:

```nix
{
  nixpkgs.overlays = [ inputs.appgrid.overlays.default ];
  environment.systemPackages = [ pkgs.appgrid ];
}
```

## Classic Nix (no flakes)

```bash
nix-build packaging/nix/package.nix
```

Or with `callPackage` from your own overlay:

```nix
self: super: {
  appgrid = super.callPackage ./packaging/nix/package.nix { };
}
```

## Versioning

`package.nix` parses the version out of `CMakeLists.txt` at evaluation time
(the `project(AppGrid VERSION X.Y.Z ...)` line). Building a tag with
`nix build github:xarbit/plasma6-applet-appgrid/v1.8.0-rc.3` produces a
derivation labelled `plasma6-applet-appgrid-1.8.0` automatically — no
separate bump needed in `package.nix`. The same string is fed back into
the cmake build via `APPGRID_VERSION_OVERRIDE` so the compiled binary
self-reports it too.

## Reporting issues

If a build fails on Nix specifically — wrong KF6 component versions, missing
runtime dep, etc. — open an issue at
<https://github.com/xarbit/plasma6-applet-appgrid/issues> with the output of:

```bash
nix --version
nix flake metadata github:xarbit/plasma6-applet-appgrid
```
