FROM alpine:3.8 AS build
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"

RUN apk add --no-cache build-base gcc-gnat zlib-dev

WORKDIR /ada-android
COPY ada-musl.patch ada-x86-android.patch ./

ARG NDK_URL=https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip

# Copy libraries from android ndk
RUN wget $NDK_URL \
    && unzip android-ndk-*.zip \
    && rm android-ndk-*.zip \
    # Libraries and includes for arm
    && cp -r android-ndk-*/platforms/android-14/arch-arm ndk-chain-arm \
    && cp -r android-ndk-*/sysroot/usr/include ndk-chain-arm/usr \
    && ln -s arm-linux-androideabi/asm ndk-chain-arm/usr/include \
    # Libraries and includes for x86
    && cp -r android-ndk-*/platforms/android-14/arch-x86 ndk-chain-x86 \
    && cp -r android-ndk-*/sysroot/usr/include ndk-chain-x86/usr \
    && ln -s i686-linux-android/asm ndk-chain-x86/usr/include \
    && rm -r android-ndk-*

ARG GCC_URL=https://ftp.gnu.org/gnu/gcc/gcc-6.4.0/gcc-6.4.0.tar.xz
ARG BINUTILS_URL=https://ftp.gnu.org/gnu/binutils/binutils-2.31.1.tar.xz

# Download and extract binutils, gcc, and prerequisites
RUN wget $GCC_URL $BINUTILS_URL \
    && tar xf gcc-* \
    && tar xf binutils-* \
    && rm *.tar.* \
    && mv binutils-* binutils \
    && mv gcc-* gcc \
    && cd gcc \
    && patch -p1 -i ../ada-musl.patch \
    && patch -p1 -i ../ada-x86-android.patch \
    && ./contrib/download_prerequisites

# https://developer.android.com/ndk/guides/abis#v7a
# Since Android 5.0, only PIE executables are supported.
# PIE doesn't work on 4.0 and earlier; static linking solves that.
ARG CONFIGURE_ARGS="\
    --prefix=/ada-android/toolchain \
    --enable-languages=ada \
    --enable-threads=posix \
    --disable-shared \
    --enable-default-pie \
    --disable-tls \
    --enable-initfini-array \
    --disable-nls \
    --enable-plugins \
    --disable-werror \
    --with-system-zlib \
    --disable-gdb \
    CFLAGS_FOR_TARGET=-D__ANDROID_API__=14"

ARG ARM_CONFIGURE_ARGS="\
    --target=arm-linux-androideabi \
    --with-sysroot=/ada-android/ndk-chain-arm \
    --with-arch=armv7-a \
    --with-fpu=vfpv3-d16 \
    --with-float=soft"

# Build arm binutils
RUN mkdir binutils/build-arm \
    && cd binutils/build-arm \
    && ../configure $ARM_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-arm

# Build arm gcc
RUN mkdir gcc/build-arm \
    && cd gcc/build-arm \
    && ../configure $ARM_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-arm

ARG X86_CONFIGURE_ARGS="\
    --target=i686-linux-android \
    --with-sysroot=/ada-android/ndk-chain-x86 \
    --with-arch=i686 \
    --with-sss3 \
    --with-fpmath=sse"

# Build x86 binutils
RUN mkdir binutils/build-x86 \
    && cd binutils/build-x86 \
    && ../configure $X86_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-x86

# Build x86 gcc
RUN mkdir gcc/build-x86 \
    && cd gcc/build-x86 \
    && ../configure $X86_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-x86

# Copy toolchain to a clean image
FROM alpine:3.8
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"
RUN apk add --no-cache qemu-arm
COPY --from=build /ada-android/toolchain/arm-linux-androideabi /usr/arm-linux-androideabi
COPY --from=build /ada-android/toolchain/i686-linux-android /usr/i686-linux-android
COPY --from=build /ada-android/toolchain/bin /usr/bin
COPY --from=build /ada-android/toolchain/lib /usr/lib
COPY --from=build /ada-android/toolchain/libexec /usr/libexec
COPY --from=build /ada-android/ndk-chain-arm/usr/lib /usr/arm-linux-androideabi/lib/armv7-a
COPY --from=build /ada-android/ndk-chain-x86/usr/lib /usr/i686-linux-android/lib/i686
ENV LD_LIBRARY_PATH=/usr/x86_64-pc-linux-musl/arm-linux-androideabi/lib:/usr/x86_64-pc-linux-musl/i686-linux-android/lib
