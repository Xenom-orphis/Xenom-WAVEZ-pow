# GPU Mining Guide for Xenom PoW Blockchain

Complete guide for mining Xenom blocks with CUDA GPU acceleration.

## 🚀 Quick Start

### 1. Build the GPU Miner

```bash
# Install CUDA toolkit first (if not already installed)
# Ubuntu: sudo apt install nvidia-cuda-toolkit
# See: https://developer.nvidia.com/cuda-downloads

cd xenom-miner-rust
cargo build --release --features cuda
cd ..
```

### 2. Configure Mining Settings

```bash
# Edit gpu-miner.conf for your hardware
nano gpu-miner.conf

# Or use presets:
source gpu-miner.conf  # Uses default RTX 3060 Ti preset
```

### 3. Start Mining

```bash
# Make sure your node is running first
./start-node.sh   # In another terminal

# Start GPU mining
./mine-gpu.sh
```

That's it! The script will automatically:
- Fetch mining templates from your node
- Mine blocks using GPU acceleration
- Submit valid solutions back to the node
- Loop continuously

## 📊 Performance Comparison

### GPU vs CPU Mining

| Hardware | Hash Rate | Time per Block* | Speedup |
|----------|-----------|-----------------|---------|
| **GPU: RTX 4090** | ~8 GH/s | 1-2s | 50x |
| **GPU: RTX 3090** | ~6 GH/s | 2-4s | 40x |
| **GPU: RTX 3080** | ~4 GH/s | 3-6s | 25x |
| **GPU: RTX 3060 Ti** | ~2.5 GH/s | 5-10s | 15x |
| **GPU: GTX 1080 Ti** | ~1.5 GH/s | 10-20s | 10x |
| **CPU: Ryzen 9 5950X (16 cores)** | ~150 MH/s | 30-90s | 1x |
| **CPU: i9-12900K (16 cores)** | ~180 MH/s | 25-75s | 1.2x |

*For testnet difficulty (0x1f00ffff)

## 🎯 Hardware Recommendations

### Recommended GPUs for Mining

**Best Value:**
- RTX 3060 Ti (200W, ~$400, 12.5 MH/s per watt)
- RTX 3070 (220W, ~$500, 13.6 MH/s per watt)

**High Performance:**
- RTX 3080 (320W, ~$700, 12.5 MH/s per watt)
- RTX 3090 (350W, ~$1200, 17.1 MH/s per watt)

**Maximum Hashrate:**
- RTX 4090 (450W, ~$1600, 17.8 MH/s per watt)

**Budget Options:**
- GTX 1080 Ti (250W, ~$300 used, 6 MH/s per watt)
- RTX 2070 Super (215W, ~$400, 9.3 MH/s per watt)

### System Requirements

**Minimum:**
- NVIDIA GPU (Compute Capability 6.0+, Pascal or newer)
- 4 GB GPU RAM
- 8 GB System RAM
- CUDA Toolkit 11.0+

**Recommended:**
- RTX 30xx or 40xx series
- 8 GB+ GPU RAM
- 16 GB+ System RAM
- CUDA Toolkit 11.8+
- SSD for node data

## ⚙️ Configuration Guide

### GPU Optimization Settings

Edit `gpu-miner.conf` based on your GPU:

```bash
# RTX 4090 / 3090 (32+ GB RAM)
export POPULATION="32768"
export GENERATIONS="5000"
export MUTATION_RATE="0.005"

# RTX 3080 / 3070 (10-12 GB)
export POPULATION="16384"
export GENERATIONS="3000"
export MUTATION_RATE="0.01"

# RTX 3060 Ti / 2080 (8 GB) - BALANCED
export POPULATION="8192"
export GENERATIONS="1000"
export MUTATION_RATE="0.01"

# GTX 1080 Ti / 1070 (8 GB)
export POPULATION="4096"
export GENERATIONS="1000"
export MUTATION_RATE="0.02"
```

### Parameter Explanations

| Parameter | Description | Typical Range | Impact |
|-----------|-------------|---------------|--------|
| **POPULATION** | Number of candidates per generation | 2048-32768 | GPU memory, parallelism |
| **GENERATIONS** | Max evolution iterations | 500-5000 | Time limit per attempt |
| **MUTATION_RATE** | Probability of random mutation | 0.001-0.05 | Exploration vs exploitation |
| **MV_LEN** | Mutation vector byte length | 16 | Must match protocol |

**Tuning Tips:**
- **Large population** (16k-32k) = better for powerful GPUs
- **Small population** (2k-8k) = better for older/memory-limited GPUs
- **Low mutation** (0.005) = stable convergence, slower exploration
- **High mutation** (0.02) = more randomness, may find solutions faster

## 🔧 Advanced Usage

### Multi-GPU Mining

Run separate instances for each GPU:

```bash
# Terminal 1 - GPU 0
CUDA_VISIBLE_DEVICES=0 ./mine-gpu.sh

# Terminal 2 - GPU 1
CUDA_VISIBLE_DEVICES=1 ./mine-gpu.sh

# Terminal 3 - GPU 2
CUDA_VISIBLE_DEVICES=2 ./mine-gpu.sh
```

### Performance Monitoring

```bash
# Watch GPU utilization
watch -n 0.5 nvidia-smi

# Detailed metrics
nvidia-smi dmon -s pucvmet
```

Look for:
- **GPU Util: 95-100%** ✅ (optimal)
- **GPU Util: <80%** ⚠️ (increase population)
- **Memory: <2 GB** ✅ (typical)
- **Power: Near TDP** ✅ (full performance)

### Benchmark Your Hardware

```bash
./benchmark-miner.sh
```

This will test multiple configurations and show you which performs best on your hardware.

### Optimize GPU Settings

```bash
# Set to maximum performance mode
nvidia-smi -pm 1

# Set power limit (adjust for your GPU)
sudo nvidia-smi -pl 350  # 350W for RTX 3090

# Set GPU clock offset (requires cooldown monitoring)
# nvidia-smi -lgc 1800  # Lock GPU clock to 1800 MHz
```

## 🛠️ Troubleshooting

### Common Issues

**Problem: "CUDA not found" or "nvcc not found"**

Solution:
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install nvidia-cuda-toolkit

# Add to PATH
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Add to ~/.bashrc to make permanent
```

**Problem: "Out of memory"**

Solution:
```bash
# Reduce population size
export POPULATION="4096"  # or 2048

# Free GPU memory
nvidia-smi --gpu-reset

# Check what's using GPU memory
nvidia-smi
```

**Problem: "Low hash rate / GPU util <50%"**

Solution:
```bash
# Increase population size
export POPULATION="16384"  # or 32768

# Check if GPU is throttling
nvidia-smi -q -d TEMPERATURE
nvidia-smi -q -d PERFORMANCE

# Enable performance mode
nvidia-smi -pm 1
```

**Problem: "No solutions found"**

This is normal for PoW mining! Solutions are probabilistic. Try:
```bash
# Increase generations
export GENERATIONS="5000"

# Increase population
export POPULATION="16384"

# Or just keep running - solutions will come
```

**Problem: "GPU too hot / thermal throttling"**

Solution:
```bash
# Check temperature
nvidia-smi -q -d TEMPERATURE

# Reduce power limit
sudo nvidia-smi -pl 300  # Reduce from 350W

# Improve cooling
# - Clean dust from GPU
# - Increase case airflow
# - Consider better GPU cooler
```

### Debug Mode

Enable verbose logging:
```bash
# In mine-gpu.sh, add:
set -x  # After 'set -e'

# Or run miner directly with full output
./xenom-miner-rust/target/release/xenom-miner-rust \
    --header-hex <HEADER> \
    --bits-hex 1f00ffff \
    --gpu \
    --population 8192 \
    --generations 100
```

## 📈 Expected Performance

### Hashrate Calculation

```
Hashrate = (Population × Generations × 7) / Time
```

Where `7` is the number of BLAKE3 rounds in each hash.

Example:
- Population: 8192
- Generations: 100 (in 2 seconds)
- Hashrate: (8192 × 100 × 7) / 2 = 2.87 GH/s

### Block Finding Probability

For difficulty `D` and hashrate `H`:
```
Expected time = 2^256 / (target × hashrate)
```

For testnet (0x1f00ffff):
- Target = ~1.7e70
- At 4 GH/s: ~5-10 seconds per block (probabilistic)

## 💰 Profitability

Mining profitability depends on:
1. **Electricity cost** ($/kWh)
2. **GPU power consumption** (W)
3. **Block reward** (WAVES tokens)
4. **Token price** ($/WAVES)
5. **Network difficulty**

### Example Calculation (RTX 3080)

```
Power: 320W = 0.32 kW
Cost: $0.12/kWh
Daily cost: 0.32 × 24 × $0.12 = $0.92/day

Blocks per day: 86400s / 5s avg = ~17,280 blocks
Rewards: 17,280 × 6 WAVES = 103,680 WAVES/day

Break-even if: 103,680 WAVES > $0.92
Token price needed: >$0.0000089 per WAVES
```

*Note: This is for testnet. Mainnet difficulty will be much higher.*

## 🎓 Learn More

- **Rust Miner Docs**: `xenom-miner-rust/README_GPU.md`
- **Implementation Details**: `xenom-miner-rust/GPU_IMPLEMENTATION.md`
- **Quick Start**: `xenom-miner-rust/QUICKSTART_GPU.md`
- **BLAKE3 Spec**: https://github.com/BLAKE3-team/BLAKE3-specs
- **CUDA Guide**: https://docs.nvidia.com/cuda/

## 📞 Support

- **Node issues**: Check `./start-node.sh` and node logs
- **Mining issues**: Run `./benchmark-miner.sh` to diagnose
- **GPU issues**: Check `nvidia-smi` output
- **Build issues**: Verify CUDA toolkit installation

## 🎯 Best Practices

1. **Monitor temperatures** - keep GPU under 80°C
2. **Use performance mode** - `nvidia-smi -pm 1`
3. **Benchmark first** - find optimal settings for your hardware
4. **Start conservative** - begin with default settings, then optimize
5. **Watch for solutions** - mining is probabilistic, patience required
6. **Update regularly** - git pull for latest optimizations

## 🏁 Mining Checklist

- [ ] CUDA toolkit installed and in PATH
- [ ] GPU miner built with `cargo build --release --features cuda`
- [ ] Node running (`./start-node.sh`)
- [ ] Configuration tuned for your GPU (`gpu-miner.conf`)
- [ ] Benchmark completed (`./benchmark-miner.sh`)
- [ ] Mining script running (`./mine-gpu.sh`)
- [ ] GPU utilization high (>90%)
- [ ] Temperature acceptable (<80°C)
- [ ] Blocks being found and accepted

Happy Mining! ⛏️✨
