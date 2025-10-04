#!/bin/bash

echo "📦 Installing blake3sum for verification..."

# Check if blake3sum is already available
if command -v blake3sum >/dev/null 2>&1; then
    echo "✅ blake3sum is already installed"
    blake3sum --version
    exit 0
fi

# Try different installation methods
if command -v cargo >/dev/null 2>&1; then
    echo "🦀 Installing blake3sum via Cargo..."
    cargo install b3sum
    
    # Create symlink if b3sum was installed but blake3sum doesn't exist
    if command -v b3sum >/dev/null 2>&1 && ! command -v blake3sum >/dev/null 2>&1; then
        echo "🔗 Creating blake3sum symlink..."
        ln -sf $(which b3sum) ~/.cargo/bin/blake3sum 2>/dev/null || true
    fi
elif command -v brew >/dev/null 2>&1; then
    echo "🍺 Installing blake3sum via Homebrew..."
    brew install b3sum
elif command -v apt-get >/dev/null 2>&1; then
    echo "📦 Installing blake3sum via apt..."
    sudo apt-get update && sudo apt-get install -y blake3
elif command -v yum >/dev/null 2>&1; then
    echo "📦 Installing blake3sum via yum..."
    sudo yum install -y blake3
else
    echo "❌ No package manager found. Please install blake3sum manually:"
    echo "   - Cargo: cargo install b3sum"
    echo "   - Homebrew: brew install b3sum"
    echo "   - Or download from: https://github.com/BLAKE3-team/BLAKE3"
    exit 1
fi

# Verify installation
if command -v blake3sum >/dev/null 2>&1; then
    echo "✅ blake3sum installed successfully"
    blake3sum --version
elif command -v b3sum >/dev/null 2>&1; then
    echo "✅ b3sum installed successfully"
    b3sum --version
    echo "💡 You can use 'b3sum' instead of 'blake3sum'"
else
    echo "❌ Installation failed"
    exit 1
fi
