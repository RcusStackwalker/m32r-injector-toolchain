# m32r-elf GCC + CMake Docker Toolchain

**Date:** 2026-05-18  
**Status:** Approved

## Goal

Produce a lean Docker image containing a `m32r-elf` cross-compiler (GCC) and CMake, published to `ghcr.io`. The GCC and binutils versions must be configurable via build arguments.

## Repo Structure

```
m32r-injector-toolchain/
├── .github/
│   └── workflows/
│       ├── pr.yml        # build + smoke test on every PR (no push)
│       └── release.yml   # build + push to ghcr.io on v* tag
├── Dockerfile
├── .dockerignore
├── Makefile
└── README.md
```

## Dockerfile — Multi-Stage Build

### Build Arguments

| Arg | Default | Description |
|-----|---------|-------------|
| `GCC_VERSION` | `16.1.0` | GCC source version to build |
| `BINUTILS_VERSION` | `2.44` | binutils source version to build |
| `UBUNTU_VERSION` | `24.04` | Ubuntu base image version for both stages |

### Stage 1: builder (`ubuntu:${UBUNTU_VERSION}`)

1. Install build-time deps via apt: `gcc g++ make flex bison texinfo libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev wget ca-certificates`
2. Download `binutils-${BINUTILS_VERSION}.tar.xz` from `ftp.gnu.org/gnu/binutils/`
3. Configure binutils: `--target=m32r-elf --prefix=/opt/m32r-elf --disable-nls --disable-werror`
4. `make && make install`
5. Download `gcc-${GCC_VERSION}.tar.xz` from `ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/`
6. Run `contrib/download_prerequisites` inside the GCC source tree
7. Configure GCC (out-of-tree build):
   ```
   --target=m32r-elf
   --prefix=/opt/m32r-elf
   --enable-languages=c,c++
   --without-headers
   --disable-shared
   --disable-threads
   --disable-nls
   --disable-libssp
   --disable-libgomp
   ```
8. `make && make install`

The toolchain is installed to `/opt/m32r-elf`.

### Stage 2: runner (`ubuntu:${UBUNTU_VERSION}`)

1. `apt install -y cmake libgmp10 libmpfr6 libmpc3 zlib1g`
2. `COPY --from=builder /opt/m32r-elf /opt/m32r-elf`
3. `ENV PATH=/opt/m32r-elf/bin:$PATH`

Runtime libs (`libgmp10`, `libmpfr6`, `libmpc3`, `zlib1g`) are required by the cross-compiler host binaries copied from the builder.

## Makefile

Convenience targets wrapping `docker buildx build`:

- `make build` — build with default args
- `make build GCC_VERSION=14.2.0` — override GCC version
- `make shell` — run an interactive shell in the built image
- `make push IMAGE=ghcr.io/…` — tag and push

## GitHub Actions Workflows

### `pr.yml` — Pull Request

- Trigger: `pull_request` targeting `main`
- Platform: `linux/amd64`
- Steps:
  1. Checkout
  2. Set up Docker Buildx
  3. Restore/save build cache (`type=gha`)
  4. `docker buildx build --load --platform linux/amd64`
  5. Smoke test: `docker run --rm <image> m32r-elf-gcc --version`
  6. Smoke test: `docker run --rm <image> cmake --version`

### `release.yml` — Release

- Trigger: `push` to tags matching `v*`; also `workflow_dispatch` with optional `gcc_version` and `binutils_version` inputs (when omitted, Dockerfile `ARG` defaults are used)
- Platform: `linux/amd64`
- Steps:
  1. Checkout
  2. Log in to `ghcr.io` using `GITHUB_TOKEN`
  3. Extract metadata via `docker/metadata-action` → tags `ghcr.io/<owner>/<repo>:<git-tag>` and `ghcr.io/<owner>/<repo>:latest`
  4. Set up Docker Buildx
  5. Restore/save build cache (`type=gha`)
  6. `docker buildx build --push --platform linux/amd64` with extracted tags and labels

## Constraints & Decisions

- **m32r-linux removed in GCC 12** — only `m32r-elf` (bare-metal) target is used; this remains supported in GCC 16.
- **No QEMU** — image targets `linux/amd64` only; no multi-platform builds.
- **CMake from apt** — simplest approach; version tied to Ubuntu release.
- **GCC prerequisites via `download_prerequisites`** — downloads GMP, MPFR, MPC, ISL into the GCC source tree to avoid managing them separately.
- **Out-of-tree GCC build** — required best practice for GCC; build directory is separate from source.
