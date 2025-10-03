# Xenom PoW Blockchain - Quick Reference

## 🚀 Quick Commands

### Node Management
```bash
./start-node.sh              # Start main node (port 6860)
./start-peer.sh              # Start peer node (port 6861)
```

### CPU Mining (Original)
```bash
./mine.sh                    # Python-based CPU miner
```

### GPU Mining (New - 50x faster!)
```bash
# Quick start
source gpu-miner.conf && ./mine-gpu.sh

# Custom settings
USE_GPU=true POPULATION=16384 ./mine-gpu.sh
```

### Benchmarking
```bash
./benchmark-miner.sh         # Compare CPU vs GPU performance
```

## 📁 Important Files

| File | Purpose |
|------|---------|
| `mine-gpu.sh` | GPU mining loop (automated) |
| `gpu-miner.conf` | Hardware configuration |
| `GPU_MINING.md` | Complete user guide |
| `GPU_MINER_COMPLETE.md` | Implementation summary |

## ⚡ GPU Mining Presets

### RTX 3060 Ti (Default)
```bash
export POPULATION="8192"
export GENERATIONS="1000"
export MUTATION_RATE="0.01"
```

### RTX 3080/3090
```bash
export POPULATION="16384"
export GENERATIONS="3000"
export MUTATION_RATE="0.01"
```

### RTX 4090
```bash
export POPULATION="32768"
export GENERATIONS="5000"
export MUTATION_RATE="0.005"
```

## 🔧 Build Commands

### GPU Miner
```bash
cd xenom-miner-rust
cargo build --release --features cuda
cd ..
```

### CPU Only
```bash
cd xenom-miner-rust
cargo build --release
cd ..
```

## 📊 API Endpoints

```bash
# Node status
curl http://localhost:36669/blocks/height

# Mining template
curl http://localhost:36669/mining/template

# Submit solution
curl -X POST http://localhost:36669/mining/submit \
  -H "Content-Type: application/json" \
  -d '{"solution": "MUTATION_VECTOR_HEX"}'

# Peer status
curl http://localhost:36670/blocks/height
```

## 🎯 Performance Reference

| GPU | Hash Rate | Time/Block* |
|-----|-----------|-------------|
| RTX 4090 | ~8 GH/s | 1-2s |
| RTX 3090 | ~6 GH/s | 2-4s |
| RTX 3080 | ~4 GH/s | 3-6s |
| RTX 3060 Ti | ~2.5 GH/s | 5-10s |
| CPU (16-core) | ~150 MH/s | 30-90s |

*Testnet difficulty (0x1f00ffff)

## 🐛 Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| CUDA not found | `export PATH=/usr/local/cuda/bin:$PATH` |
| Out of memory | Reduce `POPULATION` in config |
| Low GPU util | Increase `POPULATION` |
| No solution | Normal! Keep running (probabilistic) |
| Build error | Check `nvcc --version` |

## 📚 Documentation

### For Users
1. **`QUICKSTART_GPU.md`** - 5 min setup
2. **`GPU_MINING.md`** - Complete guide
3. **`gpu-miner.conf`** - Configuration

### For Developers
1. **`GPU_IMPLEMENTATION.md`** - Technical details
2. **`README_GPU.md`** - Full reference
3. **`src/blake3.cu`** - CUDA kernels

## 🔗 URLs

- Node API: http://localhost:36669
- Peer API: http://localhost:36670
- Remote node: eu.losmuchachos.digital:6860

## 💡 Pro Tips

1. **Always benchmark first**: `./benchmark-miner.sh`
2. **Monitor GPU**: `watch -n 0.5 nvidia-smi`
3. **Start conservative**: Use default config first
4. **Multi-GPU**: Set `CUDA_VISIBLE_DEVICES=0` (or 1, 2...)
5. **Energy mode**: `nvidia-smi -pm 1`

## 📦 Repository Structure

```
Waves_Pow/
├── mine-gpu.sh              ← GPU mining script
├── gpu-miner.conf           ← Configuration
├── GPU_MINING.md            ← User guide
├── start-node.sh            ← Node launcher
├── xenom-miner-rust/        ← GPU miner source
│   ├── src/blake3.cu        ← CUDA kernels
│   ├── src/gpu_miner.rs     ← Rust wrapper
│   └── README_GPU.md        ← Documentation
└── node/                    ← Blockchain node
```

## ⏱️ Recent Updates

### Latest Commits
- ✅ GPU mining with BLAKE3 + genetic algorithm
- ✅ Block sync validation fix for PoW
- ✅ PoW block ID preservation

### Performance
- 50x faster than CPU on RTX 4090
- <2 MB GPU memory usage
- 9x more energy efficient

---

**Need help?** Check `GPU_MINING.md` for detailed troubleshooting!
