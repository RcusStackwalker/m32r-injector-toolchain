# m32r-elf Toolchain Docker Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a git repository with a multi-stage Dockerfile that builds an m32r-elf cross-compiler (GCC) with CMake, published to ghcr.io via GitHub Actions.

**Architecture:** Two-stage Docker build: a builder stage compiles binutils and GCC from source targeting `m32r-elf`; a lean runner stage copies the resulting `/opt/m32r-elf` prefix and installs CMake from apt. All three versions (GCC, binutils, Ubuntu) are configurable via `ARG` defaults.

**Tech Stack:** Docker (multi-stage, BuildKit), Ubuntu 24.04, GCC 16.1.0, binutils 2.44, CMake (apt), GitHub Actions (`docker/build-push-action@v6`, `docker/metadata-action@v5`).

---

### Task 1: Initialize git repository

**Files:**
- Create: `.gitignore`
- Create: `.dockerignore`

- [ ] **Step 1: Initialize the repo**

```bash
cd /path/to/m32r-injector-toolchain
git init -b main
```

- [ ] **Step 2: Create `.gitignore`**

```
# editor artifacts
.DS_Store
*.swp
*~

# local docker tag overrides
.env
```

- [ ] **Step 3: Create `.dockerignore`**

```
.git
.github/
docs/
README.md
Makefile
.gitignore
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore .dockerignore docs/
git commit -m "chore: initialize repository with ignore files and design docs"
```

---

### Task 2: Write the Dockerfile builder stage

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Write the Dockerfile with builder stage only**

```dockerfile
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
```

- [ ] **Step 2: Verify the builder stage builds (this takes 20–40 min)**

```bash
docker buildx build --target=builder --platform linux/amd64 -t m32r-builder:test .
```

Expected: exits 0 with `m32r-elf-gcc` present in `/opt/m32r-elf/bin` inside the image.

Spot-check with:
```bash
docker run --rm m32r-builder:test ls /opt/m32r-elf/bin/m32r-elf-gcc
```
Expected: `/opt/m32r-elf/bin/m32r-elf-gcc`

---

### Task 3: Add runner stage to Dockerfile

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append runner stage to `Dockerfile`**

Add after the last line of the builder stage:

```dockerfile

# ── runner ───────────────────────────────────────────────────────────────────
FROM ubuntu:${UBUNTU_VERSION} AS runner

ARG GCC_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        libgmp10 libmpfr6 libmpc3 zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/m32r-elf /opt/m32r-elf

ENV PATH="/opt/m32r-elf/bin:${PATH}"

LABEL org.opencontainers.image.description="m32r-elf cross-compiler GCC ${GCC_VERSION} with CMake"
```

The full `Dockerfile` should now have both `builder` and `runner` stages.

- [ ] **Step 2: Build the full image**

```bash
docker buildx build --platform linux/amd64 --load -t m32r-toolchain:test .
```

Expected: exits 0, image `m32r-toolchain:test` present in local daemon.

- [ ] **Step 3: Smoke-test GCC**

```bash
docker run --rm m32r-toolchain:test m32r-elf-gcc --version
```

Expected output contains: `m32r-elf-gcc (GCC) 16.1.0`

- [ ] **Step 4: Smoke-test CMake**

```bash
docker run --rm m32r-toolchain:test cmake --version
```

Expected output starts with: `cmake version`

- [ ] **Step 5: Confirm PATH is set**

```bash
docker run --rm m32r-toolchain:test which m32r-elf-gcc
```

Expected: `/opt/m32r-elf/bin/m32r-elf-gcc`

- [ ] **Step 6: Commit**

```bash
git add Dockerfile
git commit -m "feat: add multi-stage Dockerfile for m32r-elf GCC + CMake"
```

---

### Task 4: Write the Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create `Makefile`**

```makefile
IMAGE         ?= m32r-toolchain
GCC_VERSION   ?= 16.1.0
BINUTILS_VERSION ?= 2.44
UBUNTU_VERSION   ?= 24.04

BUILD_ARGS = \
	--build-arg GCC_VERSION=$(GCC_VERSION) \
	--build-arg BINUTILS_VERSION=$(BINUTILS_VERSION) \
	--build-arg UBUNTU_VERSION=$(UBUNTU_VERSION)

.PHONY: build shell push

build:
	docker buildx build \
		--platform linux/amd64 \
		$(BUILD_ARGS) \
		--load \
		-t $(IMAGE):latest \
		.

shell:
	docker run --rm -it $(IMAGE):latest /bin/bash

push:
	docker buildx build \
		--platform linux/amd64 \
		$(BUILD_ARGS) \
		--push \
		-t $(IMAGE):latest \
		.
```

- [ ] **Step 2: Verify `make build` works**

```bash
make build
```

Expected: exits 0, produces `m32r-toolchain:latest`.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "chore: add Makefile with build/shell/push targets"
```

---

### Task 5: Write the PR workflow

**Files:**
- Create: `.github/workflows/pr.yml`

- [ ] **Step 1: Create `.github/workflows/` directory and `pr.yml`**

```bash
mkdir -p .github/workflows
```

```yaml
name: PR

on:
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          load: true
          tags: m32r-toolchain:pr
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke test — m32r-elf-gcc
        run: docker run --rm m32r-toolchain:pr m32r-elf-gcc --version

      - name: Smoke test — cmake
        run: docker run --rm m32r-toolchain:pr cmake --version
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/pr.yml'))" && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pr.yml
git commit -m "ci: add PR workflow with build and smoke tests"
```

---

### Task 6: Write the release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create `release.yml`**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      gcc_version:
        description: 'GCC version override (e.g. 16.1.0); leave blank to use Dockerfile default'
        required: false
        default: ''
      binutils_version:
        description: 'binutils version override (e.g. 2.44); leave blank to use Dockerfile default'
        required: false
        default: ''

jobs:
  push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Log in to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract image metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=raw,value=latest

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            GCC_VERSION=${{ inputs.gcc_version || '16.1.0' }}
            BINUTILS_VERSION=${{ inputs.binutils_version || '2.44' }}
```

- [ ] **Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow to publish to ghcr.io on v* tags"
```

---

### Task 7: Write README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

Write `README.md` with the following content (use triple backticks for the shell code blocks inside):

````markdown
# m32r-injector-toolchain

Docker image providing a `m32r-elf` cross-compiler (GCC) and CMake for bare-metal M32R development.

Published to: `ghcr.io/<owner>/m32r-injector-toolchain`

## Defaults

| Component  | Version |
|------------|---------|
| GCC        | 16.1.0  |
| binutils   | 2.44    |
| Ubuntu     | 24.04   |

## Pull the image

```sh
docker pull ghcr.io/<owner>/m32r-injector-toolchain:latest
```

## Use as a build environment

```sh
docker run --rm -v "$PWD":/work -w /work \
  ghcr.io/<owner>/m32r-injector-toolchain:latest \
  m32r-elf-gcc -o hello hello.c
```

## Build locally

```sh
make build
# override versions
make build GCC_VERSION=14.2.0 BINUTILS_VERSION=2.43
```

## Release a new image version

Push a tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Or trigger `workflow_dispatch` manually from GitHub Actions with optional version overrides.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage and release instructions"
```

---

### Task 8: Final verification

- [ ] **Step 1: Confirm all files are present**

```bash
find . -not -path './.git/*' | sort
```

Expected output:
```
.
./.dockerignore
./.gitignore
./.github
./.github/workflows
./.github/workflows/pr.yml
./.github/workflows/release.yml
./Dockerfile
./Makefile
./README.md
./docs
./docs/superpowers
./docs/superpowers/plans
./docs/superpowers/plans/2026-05-18-m32r-elf-toolchain-docker.md
./docs/superpowers/specs
./docs/superpowers/specs/2026-05-18-m32r-elf-toolchain-docker-design.md
```

- [ ] **Step 2: Verify git log shows clean history**

```bash
git log --oneline
```

Expected (newest first):
```
docs: add README with usage and release instructions
ci: add release workflow to publish to ghcr.io on v* tags
ci: add PR workflow with build and smoke tests
chore: add Makefile with build/shell/push targets
feat: add multi-stage Dockerfile for m32r-elf GCC + CMake
chore: initialize repository with ignore files and design docs
```

- [ ] **Step 3: Run smoke tests one final time against the local image**

```bash
docker run --rm m32r-toolchain:latest m32r-elf-gcc --version
docker run --rm m32r-toolchain:latest m32r-elf-g++ --version
docker run --rm m32r-toolchain:latest cmake --version
docker run --rm m32r-toolchain:latest m32r-elf-ld --version
```

Each command should exit 0 and print a version string.
