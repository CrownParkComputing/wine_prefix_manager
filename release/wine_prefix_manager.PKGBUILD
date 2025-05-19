# Maintainer: Your Name <your.email@example.com>
pkgname=wine_prefix_manager
pkgver=1.9.4
pkgrel=1
pkgdesc="Wine Prefix Manager"
arch=(x86_64)
url="https://github.com/jon/wine_prefix_manager"
license=(MIT)
depends=(wine)
source=("wine_prefix_manager-1.9.4-linux-x64-release.tar.gz::https://github.com/jon/wine_prefix_manager/releases/latest/download/wine_prefix_manager-1.9.4-linux-x64-release.tar.gz")
sha256sums=($(sha256sum "release/wine_prefix_manager-1.9.4-linux-x64-release.tar.gz" | awk '{print }'))

build() {
    mkdir -p build
    tar -xzf "" -C build
    cd build
    # Add any additional build steps if needed
}

package() {
    cd build
    make DESTDIR="$pkgdir/" install
}
