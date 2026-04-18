#!/bin/bash
# KTPScoreTracker compile script (WSL)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AMXX_DIR="/mnt/n/Nein_/KTP Git Projects/KTPAMXX"
INCLUDE_DIR="$AMXX_DIR/plugins/include"
COMPILER="$AMXX_DIR/obj-linux/packages/base/addons/ktpamx/scripting/amxxpc"
COMPILER_LIB="$AMXX_DIR/obj-linux/packages/base/addons/ktpamx/scripting/amxxpc32.so"
OUTPUT_DIR="$SCRIPT_DIR/compiled"
STAGING_DIR="/mnt/n/Nein_/KTP Git Projects/KTP DoD Server/serverfiles/dod/addons/ktpamx/plugins"

echo "========================================"
echo "KTPScoreTracker Plugin Compiler (WSL)"
echo "========================================"
echo ""

# Create temp build directory
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

# Validate
if [ ! -f "$COMPILER" ]; then
    echo "[ERROR] KTPAMXX compiler not found: $COMPILER"
    echo "        Build KTPAMXX first: cd KTPAMXX && ./build_linux.sh"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/KTPScoreTracker.sma" ]; then
    echo "[ERROR] Source file not found: KTPScoreTracker.sma"
    exit 1
fi

# Copy compiler and library
cp "$COMPILER" "$BUILD_DIR/"
cp "$COMPILER_LIB" "$BUILD_DIR/"
cp -r "$INCLUDE_DIR" "$BUILD_DIR/include"

# Convert line endings and copy source
sed 's/\r$//' "$SCRIPT_DIR/KTPScoreTracker.sma" > "$BUILD_DIR/KTPScoreTracker.sma"

# Compile
echo "[INFO] Compiling KTPScoreTracker.sma..."
cd "$BUILD_DIR"
./amxxpc KTPScoreTracker.sma -i./include -oKTPScoreTracker.amxx

if [ -f "KTPScoreTracker.amxx" ]; then
    mkdir -p "$OUTPUT_DIR"
    cp KTPScoreTracker.amxx "$OUTPUT_DIR/"
    echo ""
    echo "========================================"
    echo "[SUCCESS] Compilation successful!"
    echo "========================================"
    echo "Output: $OUTPUT_DIR/KTPScoreTracker.amxx"

    # Stage to server
    if [ -d "$STAGING_DIR" ]; then
        echo ""
        echo "[INFO] Staging to server..."
        cp "$OUTPUT_DIR/KTPScoreTracker.amxx" "$STAGING_DIR/"
        echo "[OK] Staged: $STAGING_DIR/KTPScoreTracker.amxx"
    fi
else
    echo ""
    echo "========================================"
    echo "[ERROR] Compilation failed!"
    echo "========================================"
    exit 1
fi

echo ""
echo "Done!"
