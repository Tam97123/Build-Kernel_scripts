#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
VERSION=$(grep -w '^VERSION' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
PATCHLEVEL=$(grep -w '^PATCHLEVEL' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
KERNEL_VERSION="${VERSION}.${PATCHLEVEL}"
REPO_URL="https://raw.githubusercontent.com/Tam97123/Build-Kernel_scripts/refs/heads/main"
TOOLCHAIN_DIR="$KERNEL_DIR/toolchain"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
DEFCONFIG_DIR=(
 "$KERNEL_DIR/arch/arm64/configs"
 "$KERNEL_DIR/arch/arm/configs"
)
# Hardcode this variable if you dont want prompt
DEFCONFIG=
KSU=

get_script() {
 local script_name="$1"
 echo "[+] Downloading $script_name..."
 if ! curl -sLO "$REPO_URL/scripts/$script_name"; then
  echo "[-] Error: Can not download $script_name!" >&2
  exit 1
 fi
 source "$script_name"
 rm -f "$script_name"
}

# ==============================================================================
# 1. CHECK KERNEL VERSION
# ==============================================================================
if [ -z "$VERSION" ] || [ -z "$PATCHLEVEL" ]; then
 echo "[-] Error: Can not detect kernel version!" >&2
 exit 1
elif [[ ( "$VERSION" -eq "5" && "$PATCHLEVEL" -gt "4" ) || "$VERSION" -gt "5" ]]; then
 echo "[-] Not supporting GKI kernel ${KERNEL_VERSION}!"
 exit 1
else
 echo "[+] Detected kernel ${KERNEL_VERSION}!"
fi

# ==============================================================================
# 2. DEPENDENCIES & OS CHECK
# ==============================================================================
install_dependencies () {
 echo "[+] Detecting OS and installing dependencies..."
 if command -v apt &> /dev/null; then
  echo "[+] Ubuntu/Debian-based system detected, using apt..."
   sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
   default-jdk gnupg flex bison gperf build-essential zip curl ccache libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
   make sudo bc grep tofrodos python3-markdown libxml2-utils xsltproc libtinfo6 \
   repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd libyaml-dev --fix-missing
  wget https://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb && sudo dpkg -i libtinfo5_6.3-2_amd64.deb && rm -f libtinfo5_6.3-2_amd64.deb
  wget https://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncurses5_6.3-2_amd64.deb && sudo dpkg -i libncurses5_6.3-2_amd64.deb && rm -f libncurses5_6.3-2_amd64.deb
 elif command -v dnf &> /dev/null; then
  echo "[+] Fedora/RHEL-based system detected, using dnf..."
  sudo dnf group install -y "c-development" "development-tools"
  sudo dnf install -y dtc lz4 xz zlib-devel java-latest-openjdk-devel python3 \
   p7zip p7zip-plugins android-tools erofs-utils \
   ncurses-devel ccache libX11-devel readline-devel mesa-libGL-devel python3-markdown \
   libxml2 libxslt dos2unix kmod openssl elfutils-libelf-devel dwarves \
   openssl-devel libarchive zstd rsync libyaml-devel openssl-devel-engine --skip-unavailable
 elif command -v pacman &> /dev/null; then
  echo "[+] Arch-based system detected, using pacman..."
  sudo pacman -Sy --needed --noconfirm base-devel
  sudo pacman -S --needed --noconfirm dtc lz4 xz zlib jdk-openjdk python \
   p7zip android-tools erofs-utils \
   ncurses ccache libx11 readline mesa python-markdown \
   libxml2 libxslt dos2unix kmod openssl libelf pahole \
   libarchive zstd rsync libyam
 else
  echo "[-] Error: Can not determine package manager, please install dependencies manually" >&2
  exit 1
  fi
  touch .requirements
}

if [ ! -f ".requirements" ]; then install_dependencies; fi

# ==============================================================================
# 3. CHECK DEFCONFIG
# ==============================================================================
check_defconfigs() {
 local input_configs="$1"
 local check_defconfigs_name=
 local check_defconfigs_path=

 for config in $input_configs; do
  local config_path=$(find "${DEFCONFIG_DIR[@]}" -type f -name "$config" -print -quit 2>/dev/null)
  if [ -n "$config_path" ]; then
   local rel_name="$config_path"
   for dir in "${DEFCONFIG_DIR[@]}"; do rel_name="${rel_name#$dir/}"; done
   check_defconfigs_name="$check_defconfigs_name $rel_name"
   check_defconfigs_path="$check_defconfigs_path $config_path"
  else
   echo "[-] Error: No such defconfig name ${config}" >&2
   return 1
  fi
 done
 DEFCONFIGS_NAMES="${check_defconfigs_name# }"
 DEFCONFIGS_PATHS="${check_defconfigs_path# }"
 return 0
}

if [ -z "$DEFCONFIG" ]; then
 while true; do
  read -p "[?] Enter defconfig (supports multiple, space-separated): " user_input
  if [ -z "$user_input" ]; then
   echo -e "\n[!] Defconfig is necessary when building kernel!"
   continue
  fi
  if check_defconfigs "$user_input"; then
   DEFCONFIG="$DEFCONFIGS_NAMES"
   break
  else
   echo "Available defconfigs:"
   find "${DEFCONFIG_DIR[@]}" -maxdepth 1 -type f \( -name "*_defconfig" -o -name "*.config" \) 2>/dev/null | awk -F'/' '{print "    " $NF}'
  fi
 done
else
 if ! check_defconfigs "$DEFCONFIG"; then exit 1; fi
 DEFCONFIG="$DEFCONFIGS_NAMES"
fi
echo "[+] Using ${DEFCONFIG} as defconfig!"

# ==============================================================================
# 4. DETECT ARCHITECTURE
# ==============================================================================
if [[ "$DEFCONFIGS_PATHS" = *"/arch/arm64/configs/"* ]]; then
 export ARCH=arm64
 export CLANG_TRIPLE="aarch64-linux-gnu-"
 GCC64=true && GCC32=true
 echo "[+] Kernel's architecture is ARM64!"
elif [[ "$DEFCONFIGS_PATHS" = *"/arch/arm/configs/"* ]]; then
 export ARCH=arm
 export CLANG_TRIPLE="arm-linux-gnueabi-"
 GCC64=false && GCC32=true
 echo "[+] Kernel's architecture is ARM!"
fi

# ==============================================================================
# 5. DOWNLOAD TOOLCHAIN
# ==============================================================================
if [ ! -d "$CLANG_DIR" ]; then get_script "get_clang.sh"; fi

# Download GCC if toolchain is required
if [ "$GCC64" = true ] || [ "$GCC32" = true ]; then
 if [ ! -d "$GCC_DIR" ]; then get_script "get_gcc.sh"; fi
fi

# ==============================================================================
# (OPTIONAL) INTEGRATE KERNELSU
# ==============================================================================
integrate_ksu () {
 get_script "integrate_ksu.sh"
 echo "[+] Downloading defconfig to enable KernelSU"
 if ! curl -sL "$REPO_URL/defconfig/ksu_defconfig" -o "$KSU_DEFCONFIG"; then
  echo "[-] Error: Can not download defconfig" >&2
  exit 1
 fi
}

integrate_ksu_susfs () {
 get_script "integrate_ksu_susfs.sh"
 echo "[+] Downloading defconfig to enable KernelSU with SUSFS"
  if ! curl -sL "$REPO_URL/defconfig/ksu-susfs_defconfig" -o "$KSU_DEFCONFIG"; then
   echo "[-] Error: Can not download defconfig" >&2
   exit 1
  fi
}

if [ -z "$KSU" ]; then
 while true; do
  read -t 10 -p "Integrate KSU? [y/n]: " KSU || true
  if [[ "$KSU" = "Y" || "$KSU" = "y" || "$KSU" = "N" || "$KSU" = "n" || -z "$KSU" ]]; then
   [ -n "$KSU" ] && sed -i "s/^KSU=.*/KSU=$KSU/" "${BASH_SOURCE[0]}"
   break
  else
   echo "[?] Unknown answer: ${KSU}"
  fi
 done
fi
if [[ "$KSU" = "Y" || "$KSU" = "y" ]]; then
 KSU_DEFCONFIG="${KERNEL_DIR}/arch/${ARCH}/configs/custom.config"
 if [[ "$KERNEL_VERSION" = "3.18" || "$KERNEL_VERSION" = "4.4" ]]; then
  echo "[+] Integrate KernelSU..."
  integrate_ksu
 elif [[ "$VERSION" -eq "4" || "$KERNEL_VERSION" = "5.4" ]]; then
  echo "[+] Integrate KernelSU with SUSFS..."
  integrate_ksu_susfs
 else
  echo "[-] This kernel script does not support kernel ${KERNEL_VERSION}!" >&2
  exit 1
 fi
 DEFCONFIG="${DEFCONFIG} custom.config"
elif [[ "$KSU" = "N" || "$KSU" = "n" ]]; then
 echo "[-] Skipping integrate KernelSU!"
elif [ -z "$KSU" ]; then
 echo -e "\n[\] Skipping integrate KernelSU!"
else
 echo "[-] Error: Unknown answer: ${KSU}" >&2
 exit 1
fi

# ==============================================================================
# 6. BUILD OPTIONS
# ==============================================================================
BUILD_OPTIONS=(
 -C "${KERNEL_DIR}"
 O="${KERNEL_DIR}/out"
 -j"$(nproc)"
 ARCH="${ARCH}"
 CC="ccache ${CLANG_DIR}/bin/clang"
 CLANG_TRIPLE="${CLANG_TRIPLE}"
)

CLANG_VER=$("${CLANG_DIR}/bin/clang" --version | head -n 1 | sed 's/.*version \([0-9]*\).*/\1/')

if [ "$CLANG_VER" -ge 11 ]; then
 BUILD_OPTIONS+=( LD="${CLANG_DIR}/bin/ld.lld" LLVM=1 LLVM_IAS=1 )
elif [ "$ARCH" = "arm64" ]; then
 export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
 export CROSS_COMPILE_ARM32="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
 BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" )
else
 export CROSS_COMPILE="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
 BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
fi

# ==============================================================================
# 7. BUILDING PROCESS
# ==============================================================================
export PATH="${CLANG_DIR}/bin:${PATH}"

# Export ccache to speed up building
export USE_CCACHE=1
export CCACHE_EXEC=$(command -v ccache || echo "/usr/bin/ccache")
ccache -M 50G >/dev/null

echo "[+] Generating Defconfig..."
make "${BUILD_OPTIONS[@]}" $DEFCONFIG

echo "[+] Compiling Kernel..."
[ -f "${KERNEL_DIR}/build.log" ] && rm -f build.log
make "${BUILD_OPTIONS[@]}" 2>&1 | tee build.log
echo "[INFO] BUILD succeed!"

# ==============================================================================
# 9. PREPARING ANYKERNEL3
# ==============================================================================
ANYKERNEL3_DIR="${KERNEL_DIR}/AnyKernel3"
ZIP_NAME="Kernel_${KERNEL_VERSION}_$(date +%y%m%d).zip"
IMAGE_DIR="${KERNEL_DIR}/out/arch/${ARCH}/boot"

if [ ! -d "$ANYKERNEL3_DIR" ]; then
 echo "[+] Downloading AnyKernel3..."
 if ! git clone -q https://github.com/Tam97123/AnyKernel3-NonGKI "$ANYKERNEL3_DIR"; then
  echo "[-] Error: Can not download AnyKernel3!" >&2
  exit 1
 fi
fi

echo "[+] Copying Images..."
if [ -f "$IMAGE_DIR/Image.gz-dtb" ]; then
 cp "${IMAGE_DIR}/Image.gz-dtb" "$ANYKERNEL3_DIR/"
elif [ -f "$IMAGE_DIR/Image" ]; then
 cp "${IMAGE_DIR}/Image" "$ANYKERNEL3_DIR/"
fi
find "${KERNEL_DIR}/out" -type f -name "*.img" 2>/dev/null | while read -r img_file; do cp "$img_file" "$ANYKERNEL3_DIR/"; done


if grep -qE "\.ko|Building modules|INSTALL_MOD_PATH" build.log 2>/dev/null && [ -n "$(find "${KERNEL_DIR}/out" -type f -name "*.ko" -print -quit 2>/dev/null)" ]; then
 echo "[+] Copying modules (.ko)..."
 MODULES_PATH="${ANYKERNEL3_DIR}/modules/system/lib/modules"
 mkdir -p "$MODULES_PATH"
 find "${KERNEL_DIR}/out" -type f -name "*.ko" -exec cp {} "$MODULES_PATH/" \;
 sed -i 's/do\.modules=0/do.modules=1/' "${ANYKERNEL3_DIR}/anykernel.sh"
fi

# ==============================================================================
# 10. PACKAGE ANYKERNEL3 ZIP
# ==============================================================================
echo "[+] Creating AnyKernel3.zip..."
cd "$ANYKERNEL3_DIR"
zip -r9 "${KERNEL_DIR}/${ZIP_NAME}" . -x "*.git*" > /dev/null && rm -rf "$ANYKERNEL3_DIR"
echo "[INFO] AnyKernel3 created at ${KERNEL_DIR}/${ZIP_NAME}"
