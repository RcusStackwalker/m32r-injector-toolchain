ARG UBUNTU_VERSION=26.04
ARG GCC_VERSION=16.1.0
ARG BINUTILS_VERSION=2.44
ARG CODEINJECTOR_VERSION=0.1.2

# ── codeinjector builder ──────────────────────────────────────────────────────
# Compiles the codeinjector binary from source for the target architecture.
# Using cargo install avoids arch-specific wheel URLs.
FROM rust:slim-bookworm AS codeinjector-builder

ARG CODEINJECTOR_VERSION
RUN cargo install \
        --git https://github.com/RcusStackwalker/codeinjector.git \
        --tag "v${CODEINJECTOR_VERSION}" \
        --locked \
        --root /usr/local \
        codeinjector

# ── m32r toolchain builder ────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG GCC_VERSION
ARG BINUTILS_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc g++ make flex bison texinfo file \
        libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
        wget ca-certificates xz-utils bzip2 \
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
        --with-newlib \
        --disable-shared \
        --disable-threads \
        --disable-nls \
        --disable-libssp \
        --disable-libgomp \
        --disable-libstdcxx \
    && make -j"$(nproc)" \
    && make install \
    && cd /build \
    && rm -rf "gcc-${GCC_VERSION}" "gcc-${GCC_VERSION}.tar.xz" gcc-build

# ── runner ────────────────────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION} AS runner

ARG GCC_VERSION
ARG CODEINJECTOR_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        make \
        cmake \
        libgmp10 libmpfr6 libmpc3 zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/m32r-elf /opt/m32r-elf
COPY --from=codeinjector-builder /usr/local/bin/codeinjector /usr/local/bin/codeinjector

ENV PATH="/opt/m32r-elf/bin:${PATH}"

LABEL org.opencontainers.image.description="m32r-elf cross-compiler GCC ${GCC_VERSION} with codeinjector ${CODEINJECTOR_VERSION}"
