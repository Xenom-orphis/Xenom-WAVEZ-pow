# GPU Miner Quick Start Guide

Get mining with CUDA GPU acceleration in under 5 minutes!

## 🚀 Quick Install

### Prerequisites Check

```bash
# 1. Check if you have NVIDIA GPU
nvidia-smi

# 2. Check CUDA toolkit
nvcc --version

# 3. Check Rust
rustc --version
```

### Install CUDA (if needed)

**Ubuntu/Debian:**
```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda
```

**Arch Linux:**
```bash
sudo pacman -S cuda
```

**macOS/Windows:** Download from [NVIDIA CUDA Downloads](https://developer.nvidia.com/cuda-downloads)

### Build

```bash
cd xenom-miner-rust

# GPU build
cargo build --release --features cuda

# CPU-only build (fallback)
cargo build --release
```

## ⚡ Mining in 3 Steps

### Step 1: Get Mining Template

```bash
# From your node
curl http://localhost:36669/mining/template
```

Example response:
```json
{
  "headerPrefix": "00000001af61d095...",
  "difficulty": "1f00ffff"
}
```

### Step 2: Run Miner

```bash
./target/release/xenom-miner-rust \
  --header-hex "00000001af61d095..." \
  --bits-hex "1f00ffff" \
  --gpu \
  --population 8192 \
  --generations 1000
```

### Step 3: Submit Solution

When miner finds a solution:
```
✅ SOLUTION FOUND!
   Mutation vector: 6604ccec7b6ea3f972eb14bcd0dfbc66
   Hash: 00000001af61d095195ba666c161e028...
```

Submit to node:
```bash
curl -X POST http://localhost:36669/mining/submit \
  -H "Content-Type: application/json" \
  -d '{
    "solution": "6604ccec7b6ea3f972eb14bcd0dfbc66"
  }'
```

## 🎯 Optimal Settings by GPU

### RTX 4090 / 3090
```bash
--gpu --population 32768 --generations 5000 --mutation-rate 0.005
```
Expected: ~6 GH/s, 2-5s per block

### RTX 3080 / 3070
```bash
--gpu --population 16384 --generations 3000 --mutation-rate 0.01
```
Expected: ~3 GH/s, 5-10s per block

### RTX 3060 Ti / 2080
```bash
--gpu --population 8192 --generations 2000 --mutation-rate 0.01
```
Expected: ~2 GH/s, 10-20s per block

### GTX 1080 Ti / 1070
```bash
--gpu --population 4096 --generations 1000 --mutation-rate 0.02
```
Expected: ~1 GH/s, 20-40s per block

### No GPU? Use CPU
```bash
--population 512 --generations 1000 --threads $(nproc)
```
Expected: ~150 MH/s on 16-core CPU

## 📊 Monitoring Performance

### Watch GPU Usage
```bash
watch -n 0.5 nvidia-smi
```

Look for:
- **GPU Util**: Should be 90-100%
- **Memory**: Should be <1 GB for default settings
- **Power**: Should be near TDP

### Optimize for Your GPU

**If GPU util < 80%:**
```bash
# Increase population
--population 16384  # or 32768
```

**If out of memory:**
```bash
# Decrease population
--population 4096  # or 2048
```

**If no solutions found:**
```bash
# Increase generations or mutation rate
--generations 5000 --mutation-rate 0.02
```

## 🔧 Troubleshooting

### "CUDA not found"
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

source ~/.bashrc
```

### "Out of memory"
```bash
# Free GPU memory
nvidia-smi --gpu-reset

# Or reduce population
--population 4096
```

### "Low hash rate"
```bash
# Check GPU clock
nvidia-smi -q -d CLOCK

# Enable performance mode
nvidia-smi -pm 1
nvidia-smi -pl 350  # Set power limit (adjust for your GPU)
```

### "No solution found"
This is normal! PoW mining is probabilistic. Try:
- Increasing generations: `--generations 10000`
- Increasing population: `--population 32768`
- Running multiple instances

## 🎓 Advanced Usage

### Multi-Instance Mining

Run multiple miners on different GPUs:
```bash
# Terminal 1 - GPU 0
CUDA_VISIBLE_DEVICES=0 ./target/release/xenom-miner-rust --gpu ...

# Terminal 2 - GPU 1
CUDA_VISIBLE_DEVICES=1 ./target/release/xenom-miner-rust --gpu ...
```

### Automated Mining Loop

```bash
#!/bin/bash
while true; do
    # Get template
    TEMPLATE=$(curl -s http://localhost:36669/mining/template)
    HEADER=$(echo $TEMPLATE | jq -r .headerPrefix)
    BITS=$(echo $TEMPLATE | jq -r .difficulty)
    
    # Mine
    RESULT=$(./target/release/xenom-miner-rust \
        --header-hex "$HEADER" \
        --bits-hex "$BITS" \
        --gpu --population 8192 --generations 1000)
    
    # Extract solution
    MV=$(echo "$RESULT" | grep "Mutation vector" | cut -d: -f2 | tr -d ' ')
    
    # Submit
    if [ -n "$MV" ]; then
        curl -X POST http://localhost:36669/mining/submit \
            -H "Content-Type: application/json" \
            -d "{\"solution\": \"$MV\"}"
    fi
    
    sleep 1
done
```

### Benchmark Mode

Test your hardware:
```bash
# Run 10 generations and measure
time ./target/release/xenom-miner-rust \
  --header-hex "0000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" \
  --bits-hex "1f00ffff" \
  --gpu \
  --population 8192 \
  --generations 10
```

Calculate hash rate:
```
Hash Rate = (population × generations) / time_seconds
```

## 📈 Performance Tuning

### Finding Optimal Population

```bash
# Test different population sizes
for pop in 2048 4096 8192 16384 32768; do
    echo "Testing population: $pop"
    time ./target/release/xenom-miner-rust \
        --header-hex <HEX> --bits-hex 1f00ffff \
        --gpu --population $pop --generations 10
done
```

Pick the size with highest hash rate.

### Finding Optimal Mutation Rate

```bash
# Test mutation rates
for rate in 0.001 0.005 0.01 0.02 0.05; do
    echo "Testing mutation rate: $rate"
    ./target/release/xenom-miner-rust \
        --header-hex <HEX> --bits-hex 1f00ffff \
        --gpu --population 8192 --generations 100 \
        --mutation-rate $rate
done
```

Lower rates = more stable convergence
Higher rates = more exploration

## 🎁 Pro Tips

1. **Keep generations low** (100-1000) and loop mining attempts
2. **Larger population** > more generations for GPU
3. **Monitor temperature** with `nvidia-smi -q -d TEMPERATURE`
4. **Set GPU to performance mode** before long mining sessions
5. **Close other GPU apps** (browsers, games) for maximum hashrate

## 📚 Learn More

- [Full Documentation](README_GPU.md)
- [Implementation Details](GPU_IMPLEMENTATION.md)
- [BLAKE3 Specification](https://github.com/BLAKE3-team/BLAKE3-specs)
- [CUDA Best Practices](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/)

## 🤝 Need Help?

- Check `--help` for all options
- GPU issues: Review `nvidia-smi` output
- Build issues: Ensure CUDA toolkit is properly installed
- Performance issues: Try CPU mode first to verify functionality

Happy Mining! ⛏️✨
