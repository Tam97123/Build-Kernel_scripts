#!/bin/bash

CLANG_NAME=$(grep -oE 'clang-r[0-9]+[a-z]*' "$KERNEL_DIR/build.config.common" | head -n 1)

if [ -z "$CLANG_NAME" ]; then
 echo "Error: Invaid Clang '$CLANG_NAME'."
 exit 1
elif ! git clone --filter=blob:none --no-checkout https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp_clang; then
 echo "Error: Can not fetch AOSP history from Google."
 exit 1
fi

CLANG_TARGET=$(git log -n 1 --all --diff-filter=AM --format="%H" -- "$CLANG_NAME")

cd aosp_clang
if [ -z "$CLANG_TARGET" ]; then
    echo "Error: '$CLANG_NAME' not found in AOSP history."
    cd .. && rm -rf aosp_clang
    exit 1
fi

git sparse-checkout init --cone
git sparse-checkout set "$CLANG_NAME"
git checkout "$CLANG_TARGET"

mv "$CLANG_NAME" "$CLANG_DIR"
cd .. && rm -rf aosp_clang
