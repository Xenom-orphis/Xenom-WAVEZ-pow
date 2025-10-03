# GPU Miner Implementation Summary

## Overview

A complete CUDA-accelerated BLAKE3 PoW miner with genetic algorithm optimization for the Xenom blockchain.

## Architecture Components

### 1. CUDA Kernels (`src/blake3.cu`)

Three optimized GPU kernels:

#### Kernel 1: `blake3_hash_batch`
```cuda
__global__ void blake3_hash_batch(
    const uint8_t *header_prefix,
    uint32_t header_len,
    const uint8_t *mutation_vectors,
    uint32_t mv_len,
    uint8_t *hashes,
    uint32_t population_size
)
```
- **Purpose**: Hash entire population in parallel
- **Input**: Header prefix + mutation vectors for all individuals
- **Output**: 32-byte BLAKE3 hashes for each candidate
- **Optimization**: Each thread processes one individual independently

#### Kernel 2: `evaluate_fitness`
```cuda
__global__ void evaluate_fitness(
    const uint8_t *hashes,
    const uint8_t *target_bytes,
    float *fitness,
    uint32_t population_size
)
```
- **Purpose**: Evaluate hash quality vs. target
- **Method**: Big-endian byte comparison
- **Fitness**: 1.0 for solutions, inverse distance otherwise
- **Parallel**: Each thread evaluates one hash

#### Kernel 3: `genetic_operators`
```cuda
__global__ void genetic_operators(
    const uint8_t *population_current,
    const float *fitness,
    uint8_t *population_next,
    uint32_t *random_seeds,
    uint32_t population_size,
    uint32_t mv_len,
    float mutation_rate
)
```
- **Purpose**: Create next generation
- **Selection**: Tournament selection (size 2)
- **Crossover**: Single-point
- **Mutation**: Per-byte with configurable rate
- **RNG**: Linear Congruential Generator (LCG) per thread

### 2. Rust GPU Wrapper (`src/gpu_miner.rs`)

#### Structure
```rust
pub struct GpuMiner {
    device: Arc<CudaDevice>,
    module: CudaModule,
    population_size: usize,
    mv_len: usize,
}
```

#### Main Mining Loop
```rust
pub fn mine_with_ga(
    &self,
    header_prefix: &[u8],
    target: &BigUint,
    generations: usize,
    mutation_rate: f32,
) -> Option<(Vec<u8>, [u8; 32])>
```

**Per Generation:**
1. Hash all candidates (GPU)
2. Evaluate fitness (GPU)
3. Check for solution (CPU-GPU sync)
4. Evolve population (GPU)
5. Swap buffers

### 3. CPU Fallback

Fully functional CPU-based genetic algorithm:
```rust
pub fn cpu_ga_mine(
    header_prefix: &[u8],
    target: &BigUint,
    population_size: usize,
    mv_len: usize,
    generations: usize,
    mutation_rate: f32,
) -> Option<(Vec<u8>, [u8; 32])>
```

## Build System

### Cargo Features
```toml
[features]
default = []
cuda = ["cudarc"]
```

### Build Script (`build.rs`)
- Detects `nvcc` compiler
- Compiles `.cu` to PTX
- Target: `sm_60` (Pascal+)
- Optimizations: `-O3 --use_fast_math`

### Build Commands

**GPU build:**
```bash
cargo build --release --features cuda
```

**CPU-only build:**
```bash
cargo build --release
```

## Memory Management

### GPU Memory Allocation

```
d_header_prefix      : header_len bytes (read-only)
d_target            : 32 bytes (read-only)
d_population_current: population_size × mv_len bytes
d_population_next   : population_size × mv_len bytes
d_hashes            : population_size × 32 bytes
d_fitness           : population_size × 4 bytes (f32)
d_seeds             : population_size × 4 bytes (u32)
```

**Example (population=8192, mv_len=16):**
- Population: 2 × 128 KB = 256 KB
- Hashes: 256 KB
- Fitness: 32 KB
- Seeds: 32 KB
- **Total: ~576 KB** (minimal GPU memory usage)

### Memory Transfers

**Host → Device (once per run):**
- Header prefix
- Target bytes

**Host → Device (per generation):**
- Initial population (generation 0 only)

**Device → Host (per generation):**
- Fitness array (for solution check)

**Device → Host (on solution):**
- Winning mutation vector
- Winning hash

## Performance Characteristics

### GPU Kernel Launch Configuration

```rust
let threads_per_block = 256;
let blocks = (population_size + 255) / 256;
let cfg = LaunchConfig {
    grid_dim: (blocks, 1, 1),
    block_dim: (threads_per_block, 1, 1),
    shared_mem_bytes: 0,
};
```

**Example:** population=8192
- Blocks: 32
- Threads per block: 256
- Total threads: 8192

### Expected Hash Rates

| GPU | Population | Est. Hash Rate | Power |
|-----|------------|----------------|-------|
| RTX 4090 | 32768 | ~6-8 GH/s | 450W |
| RTX 3090 | 32768 | ~5-6 GH/s | 350W |
| RTX 3080 | 16384 | ~3-4 GH/s | 320W |
| RTX 3060 Ti | 8192 | ~2-3 GH/s | 200W |
| GTX 1080 Ti | 4096 | ~1-2 GH/s | 250W |

### Bottleneck Analysis

**GPU-bound workloads:**
- BLAKE3 compression (compute-intensive)
- Large populations (>16384)

**Memory-bound workloads:**
- Small populations (<4096)
- Frequent CPU-GPU sync

**Optimal settings:**
- Population: 8192-32768
- Generations: Check every 100
- Mutation rate: 0.01

## Usage Examples

### Basic GPU Mining
```bash
./target/release/xenom-miner-rust \
  --header-hex <HEX> \
  --bits-hex 1f00ffff \
  --gpu \
  --population 8192 \
  --generations 1000
```

### High-Performance GPU
```bash
./target/release/xenom-miner-rust \
  --header-hex <HEX> \
  --bits-hex 1f00ffff \
  --gpu \
  --population 32768 \
  --generations 5000 \
  --mutation-rate 0.005
```

### CPU Fallback
```bash
./target/release/xenom-miner-rust \
  --header-hex <HEX> \
  --bits-hex 1f00ffff \
  --population 512 \
  --generations 1000
```

## Integration with Mining Loop

Replace the existing Python miner call:

```bash
# Old (Python)
python3 mine.py

# New (Rust GPU)
./xenom-miner-rust/target/release/xenom-miner-rust \
  --header-hex "$HEADER_HEX" \
  --bits-hex "$DIFFICULTY_BITS" \
  --gpu \
  --population 8192 \
  --generations 100
```

## Future Enhancements

### Short-term
- [ ] Multi-GPU support (distribute population)
- [ ] Dynamic mutation rate (adaptive)
- [ ] Elite preservation (keep top 5%)
- [ ] Progress bar with ETA

### Medium-term
- [ ] OpenCL backend (AMD GPUs)
- [ ] Metal backend (Apple Silicon)
- [ ] Hybrid CPU+GPU mode
- [ ] Checkpoint/resume support

### Long-term
- [ ] Auto-tuning for GPU model
- [ ] Pool mining integration
- [ ] Web interface for monitoring
- [ ] Distributed mining cluster

## Testing

### Unit Tests
```bash
cargo test
```

### Integration Tests
```bash
# Test CPU fallback
cargo run --release -- --header-hex <HEX> --bits-hex 1f00ffff --population 128 --generations 10

# Test GPU (if available)
cargo run --release --features cuda -- --header-hex <HEX> --bits-hex 1f00ffff --gpu --population 1024 --generations 10
```

### Benchmark
```bash
# Compare CPU vs GPU
time ./target/release/xenom-miner-rust --header-hex <HEX> --bits-hex 1f00ffff --population 512 --generations 100

time ./target/release/xenom-miner-rust --header-hex <HEX> --bits-hex 1f00ffff --gpu --population 8192 --generations 100
```

## Dependencies

### Runtime
- CUDA Runtime 11.0+ (GPU mode only)
- NVIDIA Driver 450.80.02+ (GPU mode only)

### Build
- CUDA Toolkit 11.0+ (with nvcc)
- Rust 1.70+
- C++ compiler (for CUDA)

### Crates
- `blake3`: BLAKE3 hashing (CPU fallback)
- `cudarc`: CUDA bindings
- `clap`: CLI parsing
- `rand`: RNG
- `rayon`: CPU parallelism
- `num-bigint`: Large integer math

## Troubleshooting

### Common Issues

**"CUDA device not found"**
- Check `nvidia-smi`
- Verify driver version
- Check CUDA_VISIBLE_DEVICES

**"PTX compilation failed"**
- Verify nvcc installation
- Check compute capability
- Review build.rs arch settings

**"Out of memory"**
- Reduce population size
- Check available GPU memory with `nvidia-smi`
- Close other GPU applications

**Poor performance**
- Increase population size
- Reduce CPU-GPU sync frequency
- Check GPU utilization with `nvidia-smi`

## License

MIT License - see main repository

## Credits

- BLAKE3 CUDA implementation based on reference spec
- Genetic algorithm design inspired by GPU Gems 3
- cudarc integration using official examples
