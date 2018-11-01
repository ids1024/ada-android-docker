#!/bin/sh

mkdir build
cd build
    ../configure $ARCH_CONFIGURE_ARGS $CONFIGURE_ARGS
    make -j$(nproc)
    make install-strip
cd ..
rm -rf build /toolchain/share
