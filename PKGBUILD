# Maintainer: Jason Scurtu <code@xarbit.dev>
pkgname=plasma6-applets-appgrid
pkgver=1.9.3
pkgrel=1
pkgdesc="A modern fullscreen application launcher for KDE Plasma"
arch=('x86_64')
url="https://appgrid.xarbit.dev"
license=('GPL-2.0-or-later')
provides=('appgrid')
conflicts=('appgrid')
replaces=('appgrid')
options=('!debug' 'lto')
install='packaging/aur/plasma6-applets-appgrid.install'
depends=(
    'plasma-workspace'
    'kservice'
    'ki18n'
    'kiconthemes'
    'layer-shell-qt'
    'plasma-activities-stats'
    'appstream-qt'
)
makedepends=(
    'cmake'
    'extra-cmake-modules'
    'qt6-base'
    'qt6-declarative'
    'libplasma'
    'kpackage'
    'kio'
    'kcoreaddons'
    'krunner'
    'kwindowsystem'
    'kglobalaccel'
    'kiconthemes'
    'plasma-activities-stats'
    'appstream-qt'
    'gettext'
)
source=()

pkgver() {
    grep -oP 'project\(AppGrid VERSION \K[0-9]+\.[0-9]+\.[0-9]+' "$startdir/CMakeLists.txt"
}

build() {
    cmake -B build -S "$startdir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
    cmake --build build -j$(nproc)
}

package() {
    DESTDIR="$pkgdir" cmake --install build
}
