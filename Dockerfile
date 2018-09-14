FROM alpine:3.8 AS build
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"

RUN apk add --no-cache build-base gcc-gnat zlib-dev

WORKDIR /ada-android
COPY ada-musl.patch .

ARG NDK_URL=https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip

# Copy libraries from android ndk
RUN wget $NDK_URL \
    && unzip android-ndk-*.zip \
    && rm android-ndk-*.zip \
    && mkdir -p ndk-chain/usr/lib ndk-chain/usr/include \
    && cp -r android-ndk-*/platforms/android-14/arch-arm/usr/lib/* ndk-chain/usr/lib \
    && cp -r android-ndk-*/sysroot/usr/include/* ndk-chain/usr/include \
    && ln -s arm-linux-androideabi/asm ndk-chain/usr/include \
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
    && ./contrib/download_prerequisites

# https://developer.android.com/ndk/guides/abis#v7a
# Since Android 5.0, only PIE executables are supported.
# PIE doesn't work on 4.0 and earlier; static linking solves that.
ARG CONFIGURE_ARGS="\
    --with-sysroot=/ada-android/ndk-chain \
    --prefix=/ada-android/toolchain \
    --target=arm-linux-androideabi \
    --with-float=soft \
    --with-fpu=vfpv3-d16 \
    --with-arch=armv7-a \
    --enable-languages=ada \
    --enable-threads=posix \
    --enable-shared \
    --enable-default-pie \
    --disable-tls \
    --enable-initfini-array \
    --disable-nls \
    --enable-plugins \
    --disable-werror \
    --with-system-zlib \
    --disable-gdb \
    CFLAGS_FOR_TARGET=-D__ANDROID_API__=14"

# Build binutils
RUN mkdir binutils/build \
    && cd binutils/build \
    && ../configure $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build

# Build gcc
RUN mkdir gcc/build \
    && cd gcc/build \
    && ../configure $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build

# Copy toolchain to a clean image
FROM alpine:3.8
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"
RUN apk add --no-cache qemu-arm
COPY --from=build /ada-android/toolchain/arm-linux-androideabi /usr/arm-linux-androideabi
COPY --from=build /ada-android/toolchain/x86_64-pc-linux-musl /usr/x86_64-pc-linux-musl
COPY --from=build /ada-android/toolchain/bin /usr/bin
COPY --from=build /ada-android/toolchain/lib /usr/lib
COPY --from=build /ada-android/toolchain/libexec /usr/libexec
COPY --from=build /ada-android/ndk-chain/usr/lib /usr/arm-linux-androideabi/lib/armv7-a
ENV LD_LIBRARY_PATH=/usr/x86_64-pc-linux-musl/arm-linux-androideabi/lib
