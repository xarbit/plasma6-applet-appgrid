# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Standalone Nix flake. Lives at the repo root so it resolves as
# `github:xarbit/plasma6-applet-appgrid` without `?dir=`; the derivation
# sits at `packages/nix/package.nix`. Install/usage: packages/nix/README.md.

{
  description = "AppGrid — grid application launcher for KDE Plasma 6";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      # System-independent overlay so downstream flakes get `pkgs.appgrid`.
      overlays.default = final: _prev: {
        appgrid = final.callPackage ./packages/nix/package.nix { };
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        appgrid = pkgs.callPackage ./packages/nix/package.nix { };
      in {
        packages.default = appgrid;
        packages.appgrid = appgrid;

        # Qt tests need an offscreen platform — CI builders have no display.
        checks.default = appgrid.overrideAttrs (old: {
          doCheck = true;
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DBUILD_TESTING=ON" ];
          preCheck = ''
            export QT_QPA_PLATFORM=offscreen
          '';
        });

        devShells.default = pkgs.mkShell {
          inputsFrom = [ appgrid ];
        };
      });
}
