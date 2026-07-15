#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
KERNEL_VERSION=$( (make kernelversion | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | tail -n 1) || true )
TOOLCHAIN_DIR="$KERNEL_DIR/toolchain"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
DEFCONFIG_DIR="$KERNEL_DIR/arch/arm64/configs"
REPO_URL="https://raw.githubusercontent.com/Tam97123/Build-Kernel_scripts/refs/heads/main"
# Hardcode these variable if you don't want prompt
DEFCONFIG=
CUSTOM_DEFCONFIG=

# Function to detect OS and install dependencies
install_dependencies () {
    echo "Detecting OS and installing dependencies..."
    if command -v apt &> /dev/null; then
     echo "Ubuntu/Debian-based system detected, using apt..."
     sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
      default-jdk gnupg flex bison gperf build-essential zip curl ccache libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
      make sudo bc grep tofrodos python3-markdown libxml2-utils xsltproc libtinfo6 \
      repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd libyaml-dev --fix-missing && \
      wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb
    elif command -v dnf &> /dev/null; then
     echo "Fedora/RHEL-based system detected, using dnf..."
     sudo dnf group install "c-development" "development-tools" && \
     sudo dnf install -y dtc lz4 xz zlib-devel java-latest-openjdk-devel python3 \
      p7zip p7zip-plugins android-tools erofs-utils \
      ncurses-devel ccache libX11-devel readline-devel mesa-libGL-devel python3-markdown \
      libxml2 libxslt dos2unix kmod openssl elfutils-libelf-devel dwarves \
      openssl-devel libarchive zstd rsync libyaml-devel openssl-devel-engine --skip-unavailable
    else
     echo "Error: Can not determine package manager, please install dependencies manually."
     exit 1
    fi
    touch .requirements
}

# Install the requirements for building the kernel when running the script for the first time
if [ ! -f ".requirements" ]; then
 install_dependencies
fi

build_gcc () {
    export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
    export CROSS_COMPILE_ARM32="${GCC_DIR}/arm32/bin/arm-linux-androideabi-"
    BUILD_OPTIONS=(
     -C "${KERNEL_DIR}"
     O="${KERNEL_DIR}/out"
     -j"$(nproc)"
     ARCH=arm64
     CROSS_COMPILE="${CROSS_COMPILE}"
     CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
     CC="ccache ${CLANG_DIR}/bin/clang"
     CLANG_TRIPLE=aarch64-linux-gnu-
    )
}

build_without_gcc () {
    export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
    export CROSS_COMPILE_ARM32="${GCC_DIR}/arm32/bin/arm-linux-androideabi-"
    BUILD_OPTIONS=(
     -C "${KERNEL_DIR}"
     O="${KERNEL_DIR}/out"
     -j"$(nproc)"
     ARCH=arm64
     LLVM=1
     LLVM_IAS=1
     CC="ccache ${CLANG_DIR}/bin/clang"
     CLANG_TRIPLE=aarch64-linux-gnu-
    )
}

get_gcc() {
    echo "Downloading scripts..."
    if [ ! -f "get_gcc.sh" ]; then 
     if ! curl -LO "$REPO_URL/scripts/get_gcc.sh"; then
      echo "Error: Can not download the file! Exiting..."
      exit 1
     fi
    fi
    source ./get_gcc.sh
    rm -f get_gcc.sh
}

get_clang () {
    echo "Downloading scripts..."
    if [ ! -f "get_clang.sh" ]; then 
     if ! curl -LO "$REPO_URL/scripts/get_clang.sh"; then
      echo "Error: Can not download the file! Exiting..."
      exit 1
     fi
    fi
    source ./get_clang.sh
    rm -f get_clang.sh
}

if [ -z "$KERNEL_VERSION" ]; then
 echo "Error: Can not find the kernel version! Exiting..."
 exit 1
else
 VERSION=$(echo "$KERNEL_VERSION" | cut -d. -f1)
 PATCH_LEVEL=$(echo "$KERNEL_VERSION" | cut -d. -f2)
 clear && echo "Kernel ${VERSION}.${PATCH_LEVEL}"
fi

if [[ "$VERSION" -eq "4" && "$PATCH_LEVEL" -le "14" ]]; then
 build_gcc
 if [ ! -d "$GCC_DIR" ]; then get_gcc; fi
else
 build_without_gcc
fi

if [ ! -d "$CLANG_DIR" ]; then
 get_clang
fi

if [ -z "$DEFCONFIG" ]; then
 while true; do
  if read -p "Enter defconfig: " DEFCONFIG; then
   if [ -z "$DEFCONFIG" ]; then
    echo -e "\nDefconfig is necessary when building the kernel"
   else
    DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$DEFCONFIG" -print -quit)
    if [ -n "$DEFCONFIG_PATH" ]; then
     DEFCONFIG="${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
     echo "Use '$DEFCONFIG' as defconfig"
     break
    else
     echo "Error: No such defconfig name '$DEFCONFIG'"
    fi
   fi
  else
   echo -e "\nDefconfig is necessary when building the kernel"
  fi
 done
else
 DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$DEFCONFIG" -print -quit)
 if [ -n "$DEFCONFIG_PATH" ]; then
  DEFCONFIG="${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
  echo "Use '$DEFCONFIG' as defconfig"
 else
  echo "Error: No such defconfig name '$DEFCONFIG'"
  exit 1
 fi
fi

if [ -z "$CUSTOM_DEFCONFIG" ]; then
 while true; do
  if read -t 10 -p "Enter custom defconfig: " CUSTOM_DEFCONFIG; then
   if [ -z "$CUSTOM_DEFCONFIG" ]; then
    echo -e "\nYou do not use custom defconfig"
    break
   else
    DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$CUSTOM_DEFCONFIG" -print -quit)
    if [ -n "$DEFCONFIG_PATH" ]; then
     CUSTOM_DEFCONFIG="${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
     echo "Use '$CUSTOM_DEFCONFIG' as custom defconfig"
     break
    else
     echo "Error: No such defconfig name '$CUSTOM_DEFCONFIG'"
    fi
   fi
  else 
   echo -e "\nYou do not use custom defconfig"
   break
  fi
 done
else
 DEFCONFIG_PATH=$(find "$DEFCONFIG_DIR" -type f -name "$CUSTOM_DEFCONFIG" -print -quit)
 if [ -n "$DEFCONFIG_PATH" ]; then
  CUSTOM_DEFCONFIG="${DEFCONFIG_PATH#$DEFCONFIG_DIR/}"
  echo "Use '$CUSTOM_DEFCONFIG' as custom defconfig"
 else
  echo "Error: No such defconfig name '$CUSTOM_DEFCONFIG'"
  exit 1
 fi
fi

export ARCH=arm64
export KBUILD_BUILD_USER="@Tam97123"
export PATH="${CLANG_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"

# Use ccache to speed up build
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
ccache -M 30G

#intergrate_ksu () {
#    if [ ! -f "integrate_ksu.sh" ]; then
#     echo "Downloading script..."
#     if ! curl -LO "$REPO_URL/scripts/integrate_ksu.sh"; then
#      echo "Error: Can not download script."
#      exit 1
#     fi
#    else
#     source ./integrate_ksu.sh
#    fi
#    echo "Downloading defconfig to enable KSU..."
#    if ! curl -L "$REPO_URL/defconfig/ksu_defconfig" -o "$DEFCONFIG_DIR/ksu_defconfig"; then
#     echo "Error: Can not download DEFCONFIG."
#     exit 1
#    fi
#    CUSTOM_DEFCONFIG="${CUSTOM_DEFCONFIG:+$CUSTOM_DEFCONFIG }ksu_defconfig"
#}

integrate_ksu_susfs () {
    if [ ! -f "integrate_ksu_susfs.sh" ]; then
     echo "Downloading script..."
     if ! curl -LO "$REPO_URL/scripts/integrate_ksu_susfs.sh"; then
      echo "Error: Can not download script."
      exit 1
     fi
    fi
    source ./integrate_ksu_susfs.sh
    echo "Downloading defconfig to enable KSU..."
    if ! curl -L "$REPO_URL/defconfig/ksu-susfs_defconfig" -o "$DEFCONFIG_DIR/ksu-susfs_defconfig"; then
     echo "Error: Can not download DEFCONFIG."
     exit 1
    fi
    CUSTOM_DEFCONFIG="${CUSTOM_DEFCONFIG:+$CUSTOM_DEFCONFIG }ksu-susfs_defconfig"
}

build_kernel () {
    # Make with configuration.
    if [ -z "$CUSTOM_DEFCONFIG" ]; then
     make "${BUILD_OPTIONS[@]}" "$DEFCONFIG"
    else
     make "${BUILD_OPTIONS[@]}" "$DEFCONFIG" $CUSTOM_DEFCONFIG
    fi
    # Build the kernel
    make "${BUILD_OPTIONS[@]}"
}

# Abort scripts for some kernels
if [[ "$VERSION" -lt "4" || ( "$VERSION" -eq "4" && "$PATCH_LEVEL" -eq "4" ) ]]; then
 echo "Not support kernel $VERSION.$PATCH_LEVEL! Please backport manually."
 exit 1
elif [[ "$VERSION" -ge "5" && "$PATCH_LEVEL" -gt "4" ) ]]; then
# integrate_ksu
 echo "Not support GKI kernel! Please backport manually."
 exit 1
else
 echo "Integrate KernelSU with SUSFS..."
 integrate_ksu_susfs
fi

build_kernel
