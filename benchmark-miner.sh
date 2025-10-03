#!/bin/bash
# Benchmark script to compare CPU vs GPU mining performance

set -e

MINER_BIN="./xenom-miner-rust/target/release/xenom-miner-rust"

# Test header (dummy data for benchmarking)
TEST_HEADER="00000001af61d095195ba666c161e028bdeb3df1d1a1227f0650095885f622418e2b9037000000000000000000000000000000000000000000000000000000000000000000000199a6b882ea000000001f00ffff0000000000000000000000"
TEST_BITS="1f00ffff"

echo "🏁 Xenom Miner Benchmark"
echo "================================="
echo ""

# Check if miner is built
if [ ! -f "$MINER_BIN" ]; then
    echo "Building miner (CPU version)..."
    cd xenom-miner-rust
    cargo build --release
    cd ..
    echo ""
fi

echo "Test Configuration:"
echo "  Header: ${TEST_HEADER:0:40}..."
echo "  Difficulty: 0x$TEST_BITS"
echo "  Test runs: 3 per configuration"
echo ""

# Function to run benchmark
run_benchmark() {
    local NAME=$1
    shift
    local ARGS="$@"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing: $NAME"
    echo "Command: $MINER_BIN $ARGS"
    echo ""
    
    local TOTAL_TIME=0
    local RUNS=3
    
    for i in $(seq 1 $RUNS); do
        echo -n "  Run $i/$RUNS: "
        START=$(date +%s%N)
        
        OUTPUT=$($MINER_BIN \
            --header-hex "$TEST_HEADER" \
            --bits-hex "$TEST_BITS" \
            $ARGS 2>&1 || true)
        
        END=$(date +%s%N)
        DURATION=$(( (END - START) / 1000000 ))  # Convert to milliseconds
        DURATION_SEC=$(awk "BEGIN { printf \"%.2f\", $DURATION/1000 }")
        
        echo "${DURATION_SEC}s"
        TOTAL_TIME=$(awk "BEGIN { printf \"%.2f\", $TOTAL_TIME + $DURATION_SEC }")
    done
    
    AVG_TIME=$(awk "BEGIN { printf \"%.2f\", $TOTAL_TIME / $RUNS }")
    echo ""
    echo "  Average time: ${AVG_TIME}s"
    echo ""
}

# CPU Benchmarks
echo ""
echo "═══════════════════════════════════════"
echo "CPU BENCHMARKS"
echo "═══════════════════════════════════════"
echo ""

run_benchmark "CPU Brute Force (8 threads)" \
    "--brute --threads 8 --mv-len 16"

run_benchmark "CPU GA (pop=256, gen=100)" \
    "--population 256 --generations 100 --mv-len 16"

run_benchmark "CPU GA (pop=512, gen=100)" \
    "--population 512 --generations 100 --mv-len 16"

# GPU Benchmarks (if available)
if command -v nvcc &> /dev/null; then
    echo ""
    echo "═══════════════════════════════════════"
    echo "GPU BENCHMARKS (CUDA detected)"
    echo "═══════════════════════════════════════"
    echo ""
    
    # Build GPU version if needed
    if ! $MINER_BIN --help 2>&1 | grep -q "gpu"; then
        echo "Building GPU version..."
        cd xenom-miner-rust
        cargo build --release --features cuda
        cd ..
        echo ""
    fi
    
    run_benchmark "GPU (pop=4096, gen=100)" \
        "--gpu --population 4096 --generations 100 --mutation-rate 0.01 --mv-len 16"
    
    run_benchmark "GPU (pop=8192, gen=100)" \
        "--gpu --population 8192 --generations 100 --mutation-rate 0.01 --mv-len 16"
    
    run_benchmark "GPU (pop=16384, gen=100)" \
        "--gpu --population 16384 --generations 100 --mutation-rate 0.01 --mv-len 16"
    
    echo ""
    echo "GPU Info:"
    nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader
    echo ""
else
    echo ""
    echo "═══════════════════════════════════════"
    echo "GPU BENCHMARKS - SKIPPED"
    echo "═══════════════════════════════════════"
    echo "CUDA toolkit not found. GPU benchmarks skipped."
    echo "Install CUDA from: https://developer.nvidia.com/cuda-downloads"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Benchmark complete!"
echo ""
echo "Recommendation:"
echo "  - For best performance, use the configuration with lowest average time"
echo "  - GPU is typically 20-50x faster than CPU"
echo "  - Larger populations work better on GPU, smaller on CPU"
echo ""
