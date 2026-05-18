ARG UBUNTU_VERSION=24.04
ARG GCC_VERSION=16.1.0
ARG BINUTILS_VERSION=2.44

# ── builder ──────────────────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG GCC_VERSION
ARG BINUTILS_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ make flex bison texinfo \
        libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
        wget ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Build binutils
RUN wget -q "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" \
    && tar xf "binutils-${BINUTILS_VERSION}.tar.xz" \
    && mkdir binutils-build \
    && cd binutils-build \
    && "../binutils-${BINUTILS_VERSION}/configure" \
        --target=m32r-elf \
        --prefix=/opt/m32r-elf \
        --disable-nls \
        --disable-werror \
    && make -j"$(nproc)" \
    && make install \
    && cd /build \
    && rm -rf "binutils-${BINUTILS_VERSION}" "binutils-${BINUTILS_VERSION}.tar.xz" binutils-build

# Build GCC
RUN wget -q "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" \
    && tar xf "gcc-${GCC_VERSION}.tar.xz" \
    && cd "gcc-${GCC_VERSION}" \
    && contrib/download_prerequisites \
    && cd /build \
    && mkdir gcc-build \
    && cd gcc-build \
    && "../gcc-${GCC_VERSION}/configure" \
        --target=m32r-elf \
        --prefix=/opt/m32r-elf \
        --enable-languages=c,c++ \
        --without-headers \
        --disable-shared \
        --disable-threads \
        --disable-nls \
        --disable-libssp \
        --disable-libgomp \
    && make -j"$(nproc)" \
    && make install \
    && cd /build \
    && rm -rf "gcc-${GCC_VERSION}" "gcc-${GCC_VERSION}.tar.xz" gcc-build
