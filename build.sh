#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
KERNEL_VERSION=$(echo $(make kernelversion) | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1)
TOOLCHAIN_DIR=$KERNEL_DIR/toolchain
CLANG_DIR=$TOOLCHAIN_DIR/clang
GCC_DIR=$TOOLCHAIN_DIR/gcc

# Function to detect OS and install dependencies
install_dependencies () {
    echo "Detecting OS and installing dependencies..."
    if command -v dnf &> /dev/null; then
     echo "Fedora/RHEL-based system detected, using dnf..."
     sudo dnf group install "c-development" "development-tools" && \
     sudo dnf install -y dtc lz4 xz zlib-devel java-latest-openjdk-devel python3 \
      p7zip p7zip-plugins android-tools erofs-utils \
      ncurses-devel ccache libX11-devel readline-devel mesa-libGL-devel python3-markdown \
      libxml2 libxslt dos2unix kmod openssl elfutils-libelf-devel dwarves \
      openssl-devel libarchive zstd rsync libyaml-devel openssl-devel-engine --skip-unavailable
    elif command -v apt &> /dev/null; then
     echo "Ubuntu/Debian-based system detected, using apt..."
     sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
      default-jdk git gnupg flex bison gperf build-essential zip curl ccache libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
      python3 make sudo gcc g++ bc grep tofrodos python3-markdown libxml2-utils xsltproc zlib1g-dev python-is-python3 libc6-dev libtinfo6 \
      make repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd libyaml-dev --fix-missing && wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb
    else
     echo "Error: Can not determine package manager, please install dependencies manually. Exiting..."
     exit 1
    fi

    touch .requirements
}

# Install the requirements for building the kernel when running the script for the first time
if [ ! -f ".requirements" ]; then
 install_dependencies
fi

get_gcc() {
    echo "Downloading scripts..."
    if [ ! -f "get_gcc.sh" ]; then 
     if ! curl -L https://raw.githubusercontent.com/Tam97123/NON_GKI_scripts/refs/heads/main/get_gcc.sh; then
      echo "Error: Can not download the file! Exiting..."
      exit 1
     fi
    fi
    chmod +x get_gcc.sh && source ./get_gcc.sh
}

get_clang () {
    echo "Downloading scripts..."
    if [ ! -f "get_clang.sh" ]; then 
     if ! curl -L https://raw.githubusercontent.com/Tam97123/NON_GKI_scripts/refs/heads/main/get_clang.sh; then
      echo "Error: Can not download the file! Exiting..."
      exit 1
     fi
    fi
    chmod +x get_clang.sh && source ./get_clang.sh
}

if [ -z "$KERNEL_VERSION" ]; then
 echo "Error: Can not find the kernel version! Exiting..."
 exit 1
fi

VERSION=$(echo "$KERNEL_VERSION" | cut -d. -f1)
PATCH_LEVEL=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [ $VERSION = "4" ]; then
 export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
 export CROSS_COMPILE_ARM32="${GCC_DIR}/arm32/bin/arm-linux-androideabi-"
 export BUILD_OPTIONS=(
     -C "${KERNEL_DIR}"
     O="${KERNEL_DIR}/out"
     -j"$(nproc)"
     ARCH=arm64
     CROSS_COMPILE="${CROSS_COMPILE}"
     CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
     CC="ccache ${CLANG_DIR}"
     CLANG_TRIPLE=aarch64-linux-gnu-
 )
 if [ ! -d "$GCC_DIR" ]; then
  get_gcc
 fi
elif [[ $VERSION = "5" && $PATCH_LEVEL = "4" ]]; then
 export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
 export CROSS_COMPILE_ARM32="${GCC_DIR}/arm32/bin/arm-linux-androideabi-"
 export BUILD_OPTIONS=(
     -C "${KERNEL_DIR}"
     O="${KERNEL_DIR}/out"
     -j"$(nproc)"
     ARCH=arm64
     CROSS_COMPILE="${CROSS_COMPILE}"
     CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
     CC="ccache ${CLANG_DIR}"
     CLANG_TRIPLE=aarch64-linux-gnu-
 )
 if [ ! -d "$GCC_DIR" ]; then
  get_gcc
 fi
fi

if [ ! -d "$CLANG_DIR"]; then
 get_clang
fi

export ARCH=arm64
export KBUILD_BUILD_USER="@Tam97123"
export PATH="${CLANG_DIR}/bin/clang:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH}"

build_kernel () {
    # Make default configuration.
    make "${BUILD_OPTIONS[@]}" $DEFCONFIG custom.config

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" || exit 1

}

build_kernel
