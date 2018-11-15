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
COPY build-binutils-gcc.sh ./

# https://developer.android.com/ndk/guides/abis#v7a
ENV CONFIGURE_ARGS \
    --prefix=/toolchain \
    --enable-languages=ada \
    --enable-threads=posix \
    --disable-shared \
    # Since Android 5.0, only PIE executables are supported.
    # PIE doesn't work on 4.0 and earlier; static linking solves that.
    --enable-default-pie \
    --disable-tls \
    --enable-initfini-array \
    --disable-nls \
    --enable-plugins \
    --disable-werror \
    --with-system-zlib \
    --disable-gdb \
    CFLAGS_FOR_TARGET=-D__ANDROID_API__=14


# Stage to build ARM binutils and gcc
FROM src AS gcc-arm
ENV ARCH_CONFIGURE_ARGS \
    --target=arm-linux-androideabi \
    --with-sysroot=/ndk-chain-arm \
    --with-arch=armv7-a \
    --with-fpu=vfpv3-d16 \
    --with-float=soft
RUN cd binutils && ../build-binutils-gcc.sh
RUN cd gcc && ../build-binutils-gcc.sh


# Stage to build x86 binutils and gcc
FROM src AS gcc-x86
ENV ARCH_CONFIGURE_ARGS \
    --target=i686-linux-android \
    --with-sysroot=/ndk-chain-x86 \
    --with-arch=i686 \
    --with-sss3 \
    --with-fpmath=sse \
    --enable-sjlj-exceptions
RUN cd binutils && ../build-binutils-gcc.sh
RUN cd gcc && ../build-binutils-gcc.sh


# Stage to build gprbuild
FROM alpine:edge as gprbuild
RUN apk add --no-cache build-base gcc-gnat

ARG GPRBUILD_URL=http://mirrors.cdn.adacore.com/art/591c45e2c7a447af2deecff7
ARG XMLADA_URL=http://mirrors.cdn.adacore.com/art/591aeb88c7a4473fcbb154f8

RUN wget $GPRBUILD_URL -O gprbuild.tar.gz \
    && wget $XMLADA_URL -O xmlada.tar.gz \
    && tar xf gprbuild.tar.gz \
    && tar xf xmlada.tar.gz \
    && mv gprbuild-gpl-2017-src gprbuild \
    && mv xmlada-gpl-2017-src xmlada \
    && rm *.tar.*

RUN cd gprbuild \
    && mkdir -p /toolchain/bin /toolchain/libexec/gprbuild /toolchain/share/gprconfig \
    && ./bootstrap.sh --prefix=/toolchain --with-xmlada=/xmlada


# Copy toolchain to a clean image
FROM alpine:edge
LABEL maintainer="Ian Douglas Scott <ian@iandouglasscott.com>"
RUN apk add --no-cache qemu-arm libgnat
COPY --from=gcc-arm /toolchain /usr/
COPY --from=gcc-x86 /toolchain /usr/
COPY --from=gprbuild /toolchain /usr/
COPY --from=ndk /ndk-chain-arm/usr/lib /usr/arm-linux-androideabi/lib/armv7-a
COPY --from=ndk /ndk-chain-x86/usr/lib /usr/i686-linux-android/lib
