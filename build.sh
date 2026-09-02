#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
VERSION=$(grep -w '^VERSION' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
PATCHLEVEL=$(grep -w '^PATCHLEVEL' Makefile | tr -d ' ' | cut -d= -f2 || echo "")
KERNEL_VERSION="${VERSION}.${PATCHLEVEL}"

TOOLCHAIN_DIR="$KERNEL_DIR/toolchain"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC_DIR="$TOOLCHAIN_DIR/gcc"
DEFCONFIG_DIR=(
 "$KERNEL_DIR/arch/arm64/configs"
 "$KERNEL_DIR/arch/arm/configs"
)
DEFCONFIG=""
KSU=""

# ==============================================================================
# SAMSUNG kernel?
# ==============================================================================
SAMSUNG_KERNEL=false
if [ -n "$(find drivers arch -type d -iname '*samsung*' -print -quit 2>/dev/null)" ]; then
 SAMSUNG_KERNEL=true
 echo "[+] Detected SAMSUNG kernel!"
 if [ -f "README_Kernel.txt" ]; then
  SAMSUNG_DEFCONFIG=$(grep -m 1 -oE '[a-zA-Z0-9_-]+_defconfig' README_Kernel.txt || true)
  [ -n "$SAMSUNG_DEFCONFIG" ] && DEFCONFIG="$SAMSUNG_DEFCONFIG"
 fi
 if [ -f "build_kernel.sh" ]; then
  grep -E "^export " build_kernel.sh > .samsung_exports || true
  source .samsung_exports 2>/dev/null || true
  rm -f .samsung_exports
 fi
fi

# ==============================================================================
# 1. CHECK KERNEL VERSION
# ==============================================================================
if [ -z "$VERSION" ] || [ -z "$PATCHLEVEL" ]; then
 echo "[-] Error: Can not detect kernel version!" >&2
 exit 1
elif [[ ( "$VERSION" -eq "5" && "$PATCHLEVEL" -gt "4" ) || "$VERSION" -gt "5" ]]; then
 echo "[-] This script does not support GKI kernel ${KERNEL_VERSION}!" >&2
 exit 1
else
 echo "[+] Detected kernel ${KERNEL_VERSION}!"
fi

# ==============================================================================
# 2. DEPENDENCIES & OS CHECK
# ==============================================================================
if [ ! -f ".requirements" ]; then
 echo "[+] Detecting OS and installing dependencies..."
 if command -v apt &> /dev/null; then
  sudo apt update > /dev/null 2>&1 && sudo apt install -y make gcc gcc-c++ bc bison flex pkgconf git curl tar xz zip unzip cpio rsync kmod perl python3 openssl openssl-devel openssl-devel-engine elfutils-libelf-devel dwarves ncurses-devel zlib-devel libyaml-devel lz4 zstd dtc >/dev/null 2>&1
  wget -q https://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb && sudo dpkg -i libtinfo5_6.3-2_amd64.deb > /dev/null 2>&1 && rm -f libtinfo5_6.3-2_amd64.deb
  wget -q https://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncurses5_6.3-2_amd64.deb && sudo dpkg -i libncurses5_6.3-2_amd64.deb > /dev/null 2>&1 && rm -f libncurses5_6.3-2_amd64.deb
 elif command -v dnf &> /dev/null; then
  sudo dnf group install -y "c-development" "development-tools" > /dev/null 2>&1
  sudo dnf install -y build-essential bc bison flex pkg-config git curl tar xz-utils zip unzip cpio rsync kmod perl python3 python-is-python3 libssl-dev libelf-dev pahole libncurses-dev zlib1g-dev libyaml-dev lz4 zstd device-tree-compiler > /dev/null 2>&1
 elif command -v pacman &> /dev/null; then
  sudo pacman -Sy --needed --noconfirm base-devel > /dev/null 2>&1
  sudo pacman -S --needed --noconfirm dtc lz4 xz zlib jdk-openjdk python p7zip android-tools erofs-utils ncurses ccache libx11 readline mesa python-markdown libxml2 libxslt dos2unix kmod openssl libelf pahole libarchive zstd rsync libyaml > /dev/null 2>&1
 fi
 touch .requirements
fi

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
   echo "[-] Error: No such defconfig name '${config}'! Please try again with available one:" >&2
   find "${DEFCONFIG_DIR[@]}" -maxdepth 1 -type f \( -name "*_defconfig" -o -name "*.config" \) 2>/dev/null | awk -F'/' '{print $NF}' | sort | column | sed 's/^/    /'
   return 1
  fi
 done
 DEFCONFIGS_NAMES="${check_defconfigs_name# }"
 DEFCONFIGS_PATHS="${check_defconfigs_path# }"
 return 0
}

AVAILABLE_CONFIGS=$(find "${DEFCONFIG_DIR[@]}" -maxdepth 1 -type f \( -name "*_defconfig" -o -name "*.config" \) 2>/dev/null || true)
CONFIG_COUNT=$(echo "$AVAILABLE_CONFIGS" | grep -c . || true)

if [ "$CONFIG_COUNT" -eq 1 ] && [ -z "$DEFCONFIG" ]; then
 DEFCONFIG=$(basename "$AVAILABLE_CONFIGS")
 echo "[+] Only one defconfig found ($DEFCONFIG)!"
 check_defconfigs "$DEFCONFIG"
 DEFCONFIG="$DEFCONFIGS_NAMES"
elif [ -z "$DEFCONFIG" ]; then
 while true; do
  read -p "[?] Enter defconfig (supports multiple, space-separated): " user_input
  if [ -z "$user_input" ]; then
   echo -e "\n[!] Defconfig is necessary when building kernel!"
   continue
  fi
  if check_defconfigs "$user_input"; then
   DEFCONFIG="$DEFCONFIGS_NAMES"
   break
  fi
 done
else
 check_defconfigs "$DEFCONFIG" || exit 1
 DEFCONFIG="$DEFCONFIGS_NAMES"
fi
echo "[+] Using ${DEFCONFIG} as defconfig!"

if [ "$SAMSUNG_KERNEL" = true ]; then
 cat <<EOF > "${KERNEL_DIR}/arch/${ARCH}/configs/samsung-rkp.config"
# Disable Samsung Securities
CONFIG_UH=n
CONFIG_UH_RKP=n
CONFIG_UH_LKMAUTH=n
CONFIG_UH_LKM_BLOCK=n
CONFIG_RKP_CFP_JOPP=n
CONFIG_RKP_CFP_ROPP=n
CONFIG_RKP_CFP=n
CONFIG_SECURITY_DEFEX=n
CONFIG_PROCA=n
CONFIG_FIVE=n
EOF
 DEFCONFIG="${DEFCONFIG} samsung-rkp.config"
fi
# ==============================================================================
# 4. DETECT ARCHITECTURE
# ==============================================================================
if [[ "$DEFCONFIGS_PATHS" == *"arm64"* ]]; then
 export ARCH=arm64
 export CLANG_TRIPLE="aarch64-linux-gnu-"
 echo "[+] Kernel's architecture is 64-bits!"
else
 export ARCH=arm
 export CLANG_TRIPLE="arm-linux-gnueabi-"
 echo "[+] Kernel's architecture is 32-bits!"
fi

# ==============================================================================
# 5. BUILD OPTIONS & QUIRKS
# ==============================================================================
BUILD_OPTIONS=(-C "${KERNEL_DIR}" -j"$(nproc)" ARCH="${ARCH}" )

if [[ "$SAMSUNG_KERNEL" == true && "${DEFCONFIG,,}" == *"exynos"* ]]; then
 IMAGE_DIR="${KERNEL_DIR}/arch/${ARCH}/boot"
else
 BUILD_OPTIONS+=( O="${KERNEL_DIR}/out" )
 IMAGE_DIR="${KERNEL_DIR}/out/arch/${ARCH}/boot"
fi

# ==============================================================================
# 6. TOOLCHAIN DETECTION & DOWNLOAD
# ==============================================================================
get_gcc() {
 [ ! -d "$GCC_DIR/aarch64" ] && git clone -q https://github.com/Tam97123/Google-GCC-Android -b aarch64 "$GCC_DIR/aarch64"
 [ ! -d "$GCC_DIR/arm" ] && git clone -q https://github.com/Tam97123/Google-GCC-Android -b arm32 "$GCC_DIR/arm"
 if [ "$ARCH" = "arm64" ]; then
  export CROSS_COMPILE="${GCC_DIR}/aarch64/bin/aarch64-linux-android-"
  export CROSS_COMPILE_ARM32="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
  BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" )
 else
  export CROSS_COMPILE="${GCC_DIR}/arm/bin/arm-linux-androideabi-"
  BUILD_OPTIONS+=( CROSS_COMPILE="${CROSS_COMPILE}" )
 fi
}

if ls "${KERNEL_DIR}"/build.config.* 1> /dev/null 2>&1; then
 echo "[+] Detected AOSP kernel (Using LLVM/Clang)"
 CLANG_NAME="$(grep -hoE 'clang-r?[0-9]+[a-z]*' "$KERNEL_DIR"/build.config.* 2>/dev/null | sort | uniq -c | sort -nr | awk '{print $2}' | head -n 1 || true )"
 if [ -n "$CLANG_NAME" ] && [ ! -d "$CLANG_DIR" ]; then
  git clone --filter=blob:none --no-checkout https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp_clang >/dev/null 2>&1
  cd aosp_clang
  CLANG_TARGET=$(git log -n 1 --all --diff-filter=AM --format="%H" -- "$CLANG_NAME")
  git sparse-checkout init --cone >/dev/null 2>&1
  git sparse-checkout set "$CLANG_NAME" >/dev/null 2>&1
  git checkout "$CLANG_TARGET" >/dev/null 2>&1
  mkdir -p "${CLANG_DIR%/*}"
  mv "$CLANG_NAME" "$CLANG_DIR"
  cd "$KERNEL_DIR" && rm -rf aosp_clang
 fi

 export PATH="${CLANG_DIR}/bin:${PATH}"
 export LD_LIBRARY_PATH="${CLANG_DIR}/lib:${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"
 BUILD_OPTIONS+=( CC="ccache ${CLANG_DIR}/bin/clang" CLANG_TRIPLE="${CLANG_TRIPLE}" )
 
 if [ "$VERSION" -ge "5" ]; then
  BUILD_OPTIONS+=( LD="${CLANG_DIR}/bin/ld.lld" LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ )
 else
  get_gcc
 fi
else
 echo "[+] Detected OEM kernel (Using GCC)"
 get_gcc
 BUILD_OPTIONS+=( CC="ccache ${CROSS_COMPILE}gcc" )
fi

# ==============================================================================
# 7. INTEGRATE KERNELSU
# ==============================================================================
if [ -z "$KSU" ]; then
 while true; do
  read -t 10 -p "Integrate KSU? [y/n]: " KSU || true
  if [[ "$KSU" == "Y" || "$KSU" == "y" || "$KSU" == "N" || "$KSU" == "n" || -z "$KSU" ]]; then
   [ -n "$KSU" ] && sed -i "s/^KSU=.*/KSU=$KSU/" "${BASH_SOURCE[0]}"
   break
  else
   echo "[?] Unknown answer: ${KSU}"
  fi
 done
fi

if [[ "$KSU" == "Y" || "$KSU" == "y" ]]; then
 echo "[+] Integrating KernelSU..."
 [ ! -d "$KERNEL_DIR/KernelSU" ] && curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash >/dev/null 2>&1 || true

 if [[ "$VERSION" -eq "4" || "$KERNEL_VERSION" == "5.4" ]]; then
  REJECT_DIR="$KERNEL_DIR/patch_rejects"
  echo "[+] Integrating SUSFS..."
  
  if [ ! -f "$KERNEL_DIR/.ksu_patch" ]; then
   KSU_PATCH="susfs_inline_hook_patches.sh"
   curl -sLO "https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/${KSU_PATCH}"
   bash "$KSU_PATCH" >/dev/null 2>&1 && rm -f "$KSU_PATCH"
   
   SUSFS_PATCH="susfs_patch_to_${KERNEL_VERSION}.patch"
   if curl -sLfO "https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/Patch/${SUSFS_PATCH}"; then
    patch -p1 < "$SUSFS_PATCH" || true
    rm -f "$SUSFS_PATCH"
   fi
   touch .ksu_patch
  fi
 
  if find "$KERNEL_DIR" -name "*.rej" | grep -q "."; then
   echo "[!] Warning: Collecting failed patches into $REJECT_DIR"
   mkdir -p "$REJECT_DIR"
   find "$KERNEL_DIR" -type f -name "*.rej" | while read -r rej_file; do
    rel_dir=$(dirname "${rej_file#$KERNEL_DIR/}")
    mkdir -p "$REJECT_DIR/$rel_dir"
    mv "$rej_file" "$REJECT_DIR/$rel_dir/"
   done
  fi

  echo "[+] Appending KernelSU configurations..."
  cat <<EOF > "${KERNEL_DIR}/arch/${ARCH}/configs/custom.config"
CONFIG_DEBUG_KERNEL=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
  DEFCONFIG="${DEFCONFIG} custom.config"
 elif [ "$KERNEL_VERSION" == "3.18" ]; then
  echo "[+] This script does not support SUSFS for kernel 3.18!"
  echo "[+] Appending KernelSU configurations..."
  cat <<EOF > "${KERNEL_DIR}/arch/${ARCH}/configs/custom.config"
CONFIG_DEBUG_KERNEL=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
EOF
  DEFCONFIG="${DEFCONFIG} custom.config"
 else
  echo [-] This script does not support KernelSU for kernel ${KERNEL_VERSION}. Skipping KernelSU integration!"
  sed -i "s/^KSU=y.*/KSU=n/" "${BASH_SOURCE[0]}"
 fi
elif [[ "$KSU" == "N" || "$KSU" == "n" ]]; then
 echo "[-] Skipping KernelSU integration!"
fi

# ==============================================================================
# 8. BUILDING PROCESS
# ==============================================================================
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
# 9. PACKAGE ANYKERNEL3 ZIP
# ==============================================================================
ANYKERNEL3_DIR="${KERNEL_DIR}/AnyKernel3"
ZIP_NAME="Kernel_${KERNEL_VERSION}_$(date +%y%m%d).zip"

if [ ! -d "$ANYKERNEL3_DIR" ]; then
 echo "[+] Downloading AnyKernel3..."
 git clone -q https://github.com/Tam97123/AnyKernel3-NonGKI "$ANYKERNEL3_DIR" || exit 1
fi

echo "[+] Copying Kernel Image..."
if [ -f "$IMAGE_DIR/Image.gz-dtb" ]; then
 cp "$IMAGE_DIR/Image.gz-dtb" "$ANYKERNEL3_DIR/"
elif [ -f "$IMAGE_DIR/Image.lz4-dtb" ]; then
 cp "$IMAGE_DIR/Image.lz4-dtb" "$ANYKERNEL3_DIR/"
else
 cp "$IMAGE_DIR/Image" "$ANYKERNEL3_DIR/" 2>/dev/null || true
fi

find "${KERNEL_DIR}/out" -type f -name "*.img" 2>/dev/null | while read -r img_file; do cp "$img_file" "$ANYKERNEL3_DIR/"; done

cd "$ANYKERNEL3_DIR"
zip -r9 "${KERNEL_DIR}/${ZIP_NAME}" . -x "*.git*" > /dev/null
rm -rf "$ANYKERNEL3_DIR"
echo "[INFO] AnyKernel3 created at ${KERNEL_DIR}/${ZIP_NAME}"
