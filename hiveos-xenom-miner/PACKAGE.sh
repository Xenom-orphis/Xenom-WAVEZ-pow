#!/bin/bash
# Script to package the Xenom miner for HiveOS distribution

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_NAME="xenom-miner"
VERSION="1.0.0"
ARCHIVE_NAME="${PACKAGE_NAME}-${VERSION}.tar.gz"

echo "=== Packaging Xenom Miner for HiveOS ==="
echo "Package: $PACKAGE_NAME"
echo "Version: $VERSION"
echo ""

# Check if xenom-miner-rust exists in parent directory
if [ ! -d "$PARENT_DIR/xenom-miner-rust" ]; then
    echo "❌ Error: xenom-miner-rust directory not found in $PARENT_DIR"
    echo "Please ensure the Rust miner source is available."
    exit 1
fi

# Clean any previous bin directory
rm -rf "$SCRIPT_DIR/bin"

# Build the PTX file for CUDA kernels
echo "🔨 Building CUDA PTX kernels..."
cd "$PARENT_DIR/xenom-miner-rust"
if command -v nvcc &> /dev/null; then
    nvcc --ptx src/blake3_simple.cu -o blake3_simple.ptx -arch=sm_60 --use_fast_math -O3
    echo "✅ PTX kernels built successfully"
else
    echo "⚠️  nvcc not found - skipping PTX build (will need to build on HiveOS)"
fi
cd "$PARENT_DIR"

# Build the miner binary with CUDA support
echo "🔨 Building Xenom miner binary with CUDA..."
cd "$PARENT_DIR/xenom-miner-rust"
cargo build --release --features=cuda
cd "$PARENT_DIR"

# Check if binary was built successfully
BINARY_PATH="$PARENT_DIR/xenom-miner-rust/target/release/xenom-miner-rust"
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: Failed to build miner binary"
    exit 1
fi

# Create bin directory in package and copy binary + PTX
echo "📦 Copying compiled binary and PTX kernels..."
mkdir -p "$SCRIPT_DIR/bin"
cp "$BINARY_PATH" "$SCRIPT_DIR/bin/"
chmod +x "$SCRIPT_DIR/bin/xenom-miner-rust"

# Copy PTX file if it exists
if [ -f "$PARENT_DIR/xenom-miner-rust/blake3_simple.ptx" ]; then
    cp "$PARENT_DIR/xenom-miner-rust/blake3_simple.ptx" "$SCRIPT_DIR/bin/"
    echo "✅ PTX kernels included"
fi

# Set execute permissions on shell scripts
echo "🔧 Setting execute permissions..."
chmod +x "$SCRIPT_DIR"/*.sh

# Clean up build artifacts before packaging
echo "🧹 Cleaning up temporary files..."
rm -rf "$SCRIPT_DIR/xenom-miner-rust"

# Create the archive (exclude source, only include bin/)
echo "📦 Creating archive: $ARCHIVE_NAME"
cd "$PARENT_DIR"
tar -zcvf "$ARCHIVE_NAME" \
    --exclude="hiveos-xenom-miner/.git" \
    --exclude="hiveos-xenom-miner/*.tar.gz" \
    --exclude="hiveos-xenom-miner/xenom-miner-rust" \
    --transform "s/^hiveos-xenom-miner/$PACKAGE_NAME/" \
    hiveos-xenom-miner

# Calculate file size
SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)

echo ""
echo "✅ Package created successfully!"
echo "   File: $ARCHIVE_NAME"
echo "   Size: $SIZE"
echo ""
echo "📤 Upload this file to your HiveOS rig or host it on a web server."
echo ""
echo "Installation command for HiveOS:"
echo "  tar -xzf $ARCHIVE_NAME -C /hive/miners/custom/"
echo "  chmod +x /hive/miners/custom/$PACKAGE_NAME/*.sh"
echo ""
