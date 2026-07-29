#!/bin/bash

# Integrate KernelSU (ReSukiSU)
if [ ! -d "$KERNEL_DIR/KernelSU" ]; then
 echo "Downloading KernelSU..."
 if ! curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash; then
  echo "Error: Can not download KernelSU"
  exit 1
 fi
elif [ -f "$KERNEL_DIR/KernelSU/kernel/Kbuild" ]; then
 sed -i 's|$(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))|%TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay|' "$KERNEL_DIR/KernelSU/kernel/Kbuild"
 sed -i '/-dirty/d' "$KERNEL_DIR/KernelSU/kernel/Kbuild"
fi

# Patch KernelSU manual hook
if [ ! -f "$KERNEL_DIR/syscall_hook_patches.sh" ]; then
 echo "Downloading script..."
 if ! curl -LO https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh; then
  echo "Error: Can not download script."
  exit 1
 fi
 chmod +x syscall_hook_patches.sh && bash syscall_hook_patches.sh
fi
