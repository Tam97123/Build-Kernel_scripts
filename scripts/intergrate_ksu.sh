#!/bin/bash

cd $KERNEL_DIR

# Abort scripts for kernel 4.4
if [[ "$VERSION" -eq "4" && "$PATCH_LEVEL" -eq "4" ]]; then
 echo "SUSFS does not support kernel 4.4! Use manual hook or backport manually instead."
 exit 1
fi

# Integrate KernelSU (ReSukiSU)
if [ ! -d "$KERNEL_DIR/KernelSU" ]; then
 echo "Downloading KernelSU..."
 if ! curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash; then
  echo "Error: Can not download KernelSU"
  exit 1
 fi
fi

# UI only, you can remove these or comment out
sed -i 's|$(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))|%TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay/|' "$KERNEL_DIR/KernelSU/kernel/KBuild"
sed -i '/-dirty/d' "$KERNEL_DIR/KernelSU/kernel/KBuild"

# Patch SUSFS (temporary for non gki)
if [[ "$VERSION" -lt "5" || ( "$VERSION" -eq "5" && "$PATCH_LEVEL" -eq "4" ) ]]; then
 if [ ! -f "$KERNEL_DIR/susfs_inline_hook_patches.sh" ]; then
  echo "Downloading script..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh; then
   echo "Error: Can not download script."
   exit 1
  fi
  chmod +x && ./susfs_inline_hook_patches.sh
 fi

 if [ ! -f "$KERNEL_DIR/susfs_patch_to_$VERSION.$PATCH_VERSION.patch" ]; then
  echo "Downloading patch..."
  if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/Patch/susfs_patch_to_$VERSION.$PATCH_VERSION.patch; then
   echo "Error: Can not download patch"
   exit 1
  fi
  patch -p1 < "susfs_patch_to_$VERSION.$PATCH_LEVEL.patch"
 fi
else
 echo "Temporary not support GKI kernel. Aborting..."
 exit 1
fi
