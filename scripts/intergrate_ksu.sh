#!/bin/bash

cd $KERNEL_DIR

# Abort scripts for kernel 4.4
if [[ "$VERSION" -eq "4" && "$PATCH_LEVEL" -eq "4" ]]; then
 echo "SUSFS do not support kernel 4.4! Use manual hook instead."
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

sed 's/KSU_VERSION_FULL := $(subst ",,$(CONFIG_KSU_FULL_NAME_FORMAT))/KSU_VERSION_FULL := %TAG_NAME%-%COMMIT_SHA%-t.me/noforce2pay
