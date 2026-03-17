# Maintainer: Jason Scurtu <jscurtu@gmail.com>
pkgname=plasma6-applets-appgrid
pkgver=1.6.0
pkgrel=1
pkgdesc="A modern fullscreen application launcher for KDE Plasma"
arch=('x86_64')
url="https://github.com/xarbit/plasma6-applet-appgrid"
license=('GPL-2.0-or-later')
provides=('appgrid')
conflicts=('appgrid')
replaces=('appgrid')
depends=(
    'plasma-workspace'
    'kservice'
    'ki18n'
    'layer-shell-qt'
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
    'gettext'
)
source=()

pkgver() {
    grep -oP 'project\(AppGrid VERSION \K[0-9]+\.[0-9]+\.[0-9]+' "$startdir/CMakeLists.txt"
}

build() {
    cmake -B build -S "$startdir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build -j$(nproc)
}

package() {
    DESTDIR="$pkgdir" cmake --install build
}
