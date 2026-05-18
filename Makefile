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
