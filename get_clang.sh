#!/bin/bash

CLANG_NAME=$1

if [ -z "$CLANG_NAME" ]; then
    echo "Error: Clang version name is blank."
    exit 1
fi

echo ">> Target Clang: $CLANG_NAME"
echo ">> Fetching AOSP toolchain history graph..."
git clone --filter=blob:none --no-checkout https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp_clang_meta

cd aosp_clang_meta || exit 1

TARGET_COMMIT=$(git log -n 1 --all --diff-filter=AM --format="%H" -- "$CLANG_NAME")

if [ -z "$TARGET_COMMIT" ]; then
    echo "Error: '$CLANG_NAME' not found in AOSP history."
    cd .. && rm -rf aosp_clang_meta
    exit 1
fi

git sparse-checkout init --cone
git sparse-checkout set "$CLANG_NAME"

echo ">> Downloading toolchain binaries..."
git checkout "$TARGET_COMMIT"

mv "$CLANG_NAME" ../toolchain/"$CLANG_NAME"
cd .. && rm -rf aosp_clang_meta