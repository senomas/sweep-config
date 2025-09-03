FROM debian:12-slim

# Install system dependencies
RUN --mount=type=cache,target=/var/cache/apt \
  --mount=type=cache,target=/var/lib/apt \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git wget curl xz-utils unzip \
  ninja-build gperf ccache dfu-util device-tree-compiler \
  python3 python3-pip python3-setuptools python3-wheel \
  cmake build-essential \
  && rm -rf /var/lib/apt/lists/*

# Install west cleanly via pipx (PEP 668 friendly)
RUN --mount=type=cache,target=/var/cache/apt \
  --mount=type=cache,target=/var/lib/apt \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  pipx python3-venv \
  && rm -rf /var/lib/apt/lists/* \
  && pipx install "west~=1.3" \
  && ln -s /root/.local/bin/west /usr/local/bin/west

# --- Zephyr SDK ---
ARG SDK_VER=0.16.9
ARG SDK_ARCH=x86_64
ENV ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk \
  ZEPHYR_TOOLCHAIN_VARIANT=zephyr

# Zephyr SDK (Debian 12)
ARG SDK_VER=0.16.9
ARG SDK_ARCH=x86_64
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
  ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk

RUN --mount=type=cache,target=/var/cache/apt \
  --mount=type=cache,target=/var/lib/apt \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl xz-utils file gawk bison flex \
  && rm -rf /var/lib/apt/lists/* \
  && set -eux; \
  url="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${SDK_VER}/zephyr-sdk-${SDK_VER}_linux-${SDK_ARCH}.tar.xz"; \
  curl -fL --retry 20 --retry-delay 10 -o /tmp/zephyr-sdk.tar.xz "$url"; \
  tar -C /opt -xf /tmp/zephyr-sdk.tar.xz; \
  /opt/zephyr-sdk-${SDK_VER}/setup.sh -t all -h -c; \
  ln -s /opt/zephyr-sdk-${SDK_VER} "${ZEPHYR_SDK_INSTALL_DIR}"; \
  rm -f /tmp/zephyr-sdk.tar.xz


# Toolchain environment
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr \
  ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk

WORKDIR /work

