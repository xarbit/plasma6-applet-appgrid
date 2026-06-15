# SPDX-FileCopyrightText: 2026 AppGrid Contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# AppGrid Plasma 6 applet — Nix derivation.
#
# Called from the top-level flake.nix; can also be imported standalone
# via callPackage for users on classic Nix or third-party overlays.

{ lib
, stdenv
, cmake
, gettext
, kdePackages
}:

let
  # Derive the version from CMakeLists.txt so it always matches the
  # checked-out source — no separate bump needed in this file.
  cmakeContents = builtins.readFile ../../CMakeLists.txt;
  versionMatch = builtins.match
    ".*project\\(AppGrid VERSION ([0-9.]+).*"
    cmakeContents;
  upstreamVersion = if versionMatch == null
    then throw "package.nix: could not parse VERSION from CMakeLists.txt"
    else builtins.head versionMatch;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "plasma6-applet-appgrid";
  version = upstreamVersion;

  src = lib.cleanSource ../..;

  nativeBuildInputs = [
    cmake
    gettext
    # ECM + wrapQtAppsHook must come from kdePackages — the top-level
    # aliases were Qt5's and were removed from nixpkgs after Plasma 5 EOL.
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
    kdePackages.kpackage
  ];

  buildInputs = with kdePackages; [
    qtbase
    qtdeclarative
    libplasma
    plasma-workspace
    plasma-activities
    plasma-activities-stats
    kpackage
    kio
    kservice
    ki18n
    kconfig
    kcoreaddons
    kwindowsystem
    kglobalaccel
    kiconthemes
    ksvg
    krunner
    kirigami
    layer-shell-qt
    # AppStream Qt6 bindings (kdePackages set, not the top-level attr).
    appstream-qt
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DAPPGRID_VERSION_OVERRIDE=${finalAttrs.version}"
  ];

  meta = with lib; {
    description = "Grid-style application launcher for KDE Plasma 6";
    longDescription = ''
      AppGrid is a grid-style replacement for Kickoff and Kicker with
      unified search, KRunner integration, drag-and-drop favorites
      reordering, multi-select with bulk actions, and support for
      immutable distros via a user-local Universal Package.

      This is a Plasma applet — a .so plugin with its QML compiled in,
      not a standalone executable. After installing, add the AppGrid
      widget through Plasma's "Add Widgets" dialog.
    '';
    homepage = "https://appgrid.xarbit.dev";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    # No mainProgram: AppGrid ships a Plasma applet plugin, no executable.
  };
})
