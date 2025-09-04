# ===== ZMK Docker Build Makefile =====
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

# --- Tunables ---
DOCKER        ?= docker
IMAGE         ?= zmk-build:0.16.9        # Build this image with your Dockerfile
BOARD         ?= nice_nano_v2
# Use one of: cradio_left / cradio_right (or override SHIELD=...)
LEFT_SHIELD   ?= cradio_left
RIGHT_SHIELD  ?= cradio_right

# Paths
WORKDIR       ?= $(CURDIR)
ZMK_APP_PATH  ?= zmk/app
ZMK_CONFIG    ?= $(WORKDIR)/config

# Caches (speed up subsequent runs)
WEST_CACHE    ?= .cache/.west
ZEPHYR_CACHE  ?= .cache/zephyr

PIP_CACHE   ?= .cache/pip
PIPX_HOME   ?= .cache/pipx


# Build directories (one per side)
BUILD_DIR_L   ?= build/$(BOARD)-$(LEFT_SHIELD)
BUILD_DIR_R   ?= build/$(BOARD)-$(RIGHT_SHIELD)

# Common west build flags
CMAKE_FLAGS    = -DZMK_CONFIG=/work/config

# Add Zephyr base so CMake can find it without zephyr-export
CMAKE_FLAGS   += -DZEPHYR_BASE=/work/zephyr

# Helper: run a command inside the builder image with proper mounts
CMAKE_REG ?= $(HOME)/.cmake
define DOCKER_RUN
$(DOCKER) run --rm -t --network=host \
  -v "$(WORKDIR)":/work \
  -v "$(WEST_CACHE)":/root/.west \
  -v "$(ZEPHYR_CACHE)":/root/.cache/zephyr \
  -v "$(CMAKE_REG)":/root/.cmake \
	-v "$(PIP_CACHE)":/root/.cache/pip \
  -v "$(PIPX_HOME)":/root/.local/pipx \
  -w /work \
  -e PIP_CACHE_DIR=/root/.cache/pip \
  -e PIPX_HOME=/root/.local/pipx \
  -e PIPX_BIN_DIR=/root/.local/bin \
  $(IMAGE) bash -lc '$(1)'
endef

PREP = set -e ; \
	west init -l config || true ; \
	west update --narrow --fetch-opt=--depth=1 ; \
	pipx runpip west install -r zephyr/scripts/requirements.txt ; \
	west zephyr-export || true

.PHONY: help image prepare build-left build-right build-all clean-left clean-right clean-all FORCE

help:
	@echo "Targets:"
	@echo "  image         Build the Docker builder image (expects Dockerfile in this dir)"
	@echo "  prepare       Run west init/update/export inside container"
	@echo "  build-left    Build firmware for $(BOARD) with SHIELD=$(LEFT_SHIELD)"
	@echo "  build-right   Build firmware for $(BOARD) with SHIELD=$(RIGHT_SHIELD)"
	@echo "  build-all     Build both halves"
	@echo "  clean-left    Remove $(BUILD_DIR_L)"
	@echo "  clean-right   Remove $(BUILD_DIR_R)"
	@echo "  clean-all     Remove both build dirs"

# Build the Debian-based image you set up earlier
BUILDX_CACHE ?= $(WORKDIR)/.cache/buildx

imagex:
	@if docker buildx version >/dev/null 2>&1; then \
		echo ">> Using docker buildx with cache at $(BUILDX_CACHE)"; \
		mkdir -p $(BUILDX_CACHE); \
		docker buildx create --name zmkbuilder --use >/dev/null 2>&1 || true; \
		docker buildx build \
			--network=host \
		  --cache-from type=local,src=$(BUILDX_CACHE) \
		  --cache-to type=local,dest=$(BUILDX_CACHE),mode=max \
		  -t $(IMAGE) .; \
	else \
		echo ">> buildx not found, falling back to classic docker build"; \
		docker build -t $(IMAGE) .; \
	fi

image:
	docker build --network=host -t $(IMAGE) .

# Initialize/update the west workspace
prepare: FORCE
	$(call DOCKER_RUN, \
		set -e ; \
  	pipx install "west~=1.3" ; \
		west init -l config || true ; \
		west update ; \
		west zephyr-export || true)

build-left: FORCE
	$(call DOCKER_RUN, \
		$(PREP) ; \
		mkdir -p "$(BUILD_DIR_L)" ; \
		ZEPHYR_BASE=/work/zephyr \
		west build -s "$(ZMK_APP_PATH)" -b "$(BOARD)" -d "$(BUILD_DIR_L)" -- \
			-DSHIELD=$(LEFT_SHIELD) -DZMK_CONFIG=/work/config ; \
		echo ; echo "Artifacts:" ; \
		ls -lh "$(BUILD_DIR_L)/zephyr/" | sed -n "s@^@  @p" ; \
		echo "UF2:  $(BUILD_DIR_L)/zephyr/zmk.uf2" ; \
		echo "HEX:  $(BUILD_DIR_L)/zephyr/zmk.hex" ; \
		chown -R 1000:1000 $(BUILD_DIR_L)/zephyr/ )
	cp $(BUILD_DIR_L)/zephyr/zmk.uf2 ${BOARD}-left.uf2


build-right: FORCE
	$(call DOCKER_RUN, \
		$(PREP) ; \
		mkdir -p "$(BUILD_DIR_R)" ; \
		ZEPHYR_BASE=/work/zephyr \
		west build -s "$(ZMK_APP_PATH)" -b "$(BOARD)" -d "$(BUILD_DIR_R)" -- \
			-DSHIELD=$(RIGHT_SHIELD) -DZMK_CONFIG=/work/config ; \
		echo ; echo "Artifacts:" ; \
		ls -lh "$(BUILD_DIR_R)/zephyr/" | sed -n "s@^@  @p" ; \
		echo "UF2:  $(BUILD_DIR_R)/zephyr/zmk.uf2" ; \
		echo "HEX:  $(BUILD_DIR_R)/zephyr/zmk.hex" ; \
		chown -R 1000:1000 $(BUILD_DIR_R)/zephyr/ )
	cp $(BUILD_DIR_R)/zephyr/zmk.uf2 ${BOARD}-right.uf2

build-all: build-left build-right

clean-left:
	sudo rm -rf "$(BUILD_DIR_L)"

clean-right:
	sudo rm -rf "$(BUILD_DIR_R)"

clean-all: clean-left clean-right
	sudo rm -rf ${WEST_CACHE}
	sudo rm -rf ${ZEPHYR_CACHE}

