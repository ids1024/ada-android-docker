# Stage extracting libraries and includes from the Android NDK
FROM alpine:edge AS ndk
ARG NDK_URL=https://dl.google.com/android/repository/android-ndk-r17c-linux-x86_64.zip

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


# Stage installing build depends and downloading/patching toolchain source
FROM ndk as src
RUN apk add --no-cache build-base gcc-gnat zlib-dev

ARG GCC_URL=https://ftp.gnu.org/gnu/gcc/gcc-8.2.0/gcc-8.2.0.tar.xz
ARG BINUTILS_URL=https://ftp.gnu.org/gnu/binutils/binutils-2.31.1.tar.xz

# Download and extract binutils, gcc, and prerequisites
COPY ada-musl.patch ada-x86-android.patch download_prerequisites-busybox.patch ./
RUN wget $GCC_URL $BINUTILS_URL \
    && tar xf gcc-* \
    && tar xf binutils-* \
    && rm *.tar.* \
    && mv binutils-* binutils \
    && mv gcc-* gcc \
    && cd gcc \
    && patch -p1 -i ../ada-musl.patch \
    && patch -p1 -i ../ada-x86-android.patch \
    && patch -p1 -i ../download_prerequisites-busybox.patch \
    && ./contrib/download_prerequisites

# https://developer.android.com/ndk/guides/abis#v7a
# Since Android 5.0, only PIE executables are supported.
# PIE doesn't work on 4.0 and earlier; static linking solves that.
ENV CONFIGURE_ARGS="\
    --prefix=/toolchain \
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


# Stage to build ARM binutils and gcc
FROM src AS gcc-arm
ENV ARM_CONFIGURE_ARGS="\
    --target=arm-linux-androideabi \
    --with-sysroot=/ndk-chain-arm \
    --with-arch=armv7-a \
    --with-fpu=vfpv3-d16 \
    --with-float=soft"

RUN mkdir binutils/build-arm \
    && cd binutils/build-arm \
    && ../configure $ARM_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-arm

RUN mkdir gcc/build-arm \
    && cd gcc/build-arm \
    && ../configure $ARM_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-arm /toolchain/share


# Stage to build x86 binutils and gcc
FROM src AS gcc-x86
ENV X86_CONFIGURE_ARGS="\
    --target=i686-linux-android \
    --with-sysroot=/ndk-chain-x86 \
    --with-arch=i686 \
    --with-sss3 \
    --with-fpmath=sse \
    --enable-sjlj-exceptions"

RUN mkdir binutils/build-x86 \
    && cd binutils/build-x86 \
    && ../configure $X86_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-x86

RUN mkdir gcc/build-x86 \
    && cd gcc/build-x86 \
    && ../configure $X86_CONFIGURE_ARGS $CONFIGURE_ARGS \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. \
    && rm -r build-x86 /toolchain/share


# Copy toolchain to a clean image
FROM alpine:edge
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"
RUN apk add --no-cache qemu-arm
COPY --from=gcc-arm /toolchain /usr/
COPY --from=gcc-x86 /toolchain /usr/
COPY --from=ndk /ndk-chain-arm/usr/lib /usr/arm-linux-androideabi/lib/armv7-a
COPY --from=ndk /ndk-chain-x86/usr/lib /usr/i686-linux-android/lib
