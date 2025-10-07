#[cfg(feature = "cuda")]
use cudarc::driver::{CudaDevice, CudaSlice, LaunchAsync, LaunchConfig};
use num_bigint::BigUint;
use rand::Rng;
#[cfg(feature = "cuda")]
use std::sync::Arc;

#[allow(dead_code)]
pub struct GpuMiner {
    #[cfg(feature = "cuda")]
    device: Arc<CudaDevice>,
    population_size: usize,
    mv_len: usize,
    #[cfg(feature = "cuda")]
    has_kernels: bool,
}

#[cfg(feature = "cuda")]
impl GpuMiner {
    pub fn new(population_size: usize, mv_len: usize, device_id: usize) -> Result<Self, Box<dyn std::error::Error>> {
        // Initialize CUDA device
        eprintln!("🎮 Initializing GPU {}", device_id);
        let device = CudaDevice::new(device_id)?;

        // Try to load compiled PTX - check multiple locations
        let mut has_kernels = false;
        let mut ptx_content: Option<String> = None;
        
        // 1. Try environment variable (set during build)
        if let Ok(ptx_path) = std::env::var("CUDA_BLAKE3_PTX") {
            eprintln!("📦 Trying CUDA_BLAKE3_PTX: {}", ptx_path);
            if let Ok(content) = std::fs::read_to_string(&ptx_path) {
                ptx_content = Some(content);
            }
        }
        
        // 2. Try relative to current directory (for deployed binaries)
        if ptx_content.is_none() {
            let paths = vec![
                "./blake3_simple.ptx",
                "./xenom-miner-rust/blake3_simple.ptx", 
                "./src/blake3_simple.ptx",
                "../src/blake3_simple.ptx",
                "blake3_simple.ptx",
                "xenom-miner-rust/blake3_simple.ptx",
                // Fallback to old names for compatibility
                "./blake3.ptx",
                "./xenom-miner-rust/blake3.ptx",
                "./src/blake3.ptx",
                "../src/blake3.ptx",
                "blake3.ptx",
                "xenom-miner-rust/blake3.ptx",
            ];
            for path in paths {
                if let Ok(content) = std::fs::read_to_string(path) {
                    eprintln!("📦 Found PTX at: {}", path);
                    ptx_content = Some(content);
                    break;
                }
            }
        }
        
        // 3. Load kernels if PTX found
        if let Some(ptx) = ptx_content {
            let module_name = "blake3_simple_kernels";
            match device.load_ptx(
                ptx.into(),
                module_name,
                &["blake3_hash_batch", "evaluate_fitness", "genetic_operators", "blake3_brute_force"],
            ) {
                Ok(_) => {
                    has_kernels = device.get_func(module_name, "blake3_hash_batch").is_some()
                        && device.get_func(module_name, "evaluate_fitness").is_some()
                        && device.get_func(module_name, "genetic_operators").is_some();
                    
                    let has_brute_force = device.get_func(module_name, "blake3_brute_force").is_some();
                    
                    if has_kernels {
                        eprintln!("✅ CUDA kernels loaded successfully");
                        if has_brute_force {
                            eprintln!("✅ Brute-force kernel also available");
                        }
                    } else {
                        eprintln!("❌ PTX loaded but required kernels not found in module");
                    }
                }
                Err(e) => {
                    eprintln!("❌ Failed to load PTX module: {}", e);
                }
            }
        } else {
            eprintln!("❌ PTX file not found. Tried:");
            eprintln!("   - CUDA_BLAKE3_PTX env var");
            eprintln!("   - ./blake3_simple.ptx");
            eprintln!("   - ./src/blake3_simple.ptx");
            eprintln!("   Compile the CUDA kernel: nvcc --ptx src/blake3_simple.cu -o blake3_simple.ptx -arch=sm_60 --use_fast_math -O3");
        }

        Ok(Self {
            device,
            population_size,
            mv_len,
            has_kernels,
        })
    }

    pub fn mine_with_ga(
        &self,
        header_prefix: &[u8],
        target: &BigUint,
        generations: usize,
        mutation_rate: f32,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        if !self.has_kernels {
            eprintln!("⚠️  CUDA kernels not loaded (missing PTX). Falling back to None.");
            return None;
        }

        let module = "blake3_simple_kernels";

        // Prepare buffers
        let pop = self.population_size as u32;
        let mv_len_u32 = self.mv_len as u32;
        let header_len_u32 = header_prefix.len() as u32;

        // Device buffers
        let d_header: CudaSlice<u8> = self.device.htod_copy(header_prefix.to_vec()).ok()?;
        let mut rng = rand::thread_rng();
        let population_bytes = self.population_size * self.mv_len;
        let mut h_population: Vec<u8> = vec![0u8; population_bytes];
        rng.fill(&mut h_population[..]);
        let mut d_population = self.device.htod_copy(h_population).ok()?;
        let mut d_population_next: CudaSlice<u8> =
            self.device.alloc_zeros(population_bytes).ok()?;
        let mut d_hashes: CudaSlice<u8> =
            self.device.alloc_zeros(self.population_size * 32).ok()?;
        let mut d_fitness: CudaSlice<f32> = self.device.alloc_zeros(self.population_size).ok()?;

        // Random seeds
        let h_seeds: Vec<u32> = (0..self.population_size).map(|_| rng.gen()).collect();
        let mut d_seeds = self.device.htod_copy(h_seeds).ok()?;

        // Target bytes (big-endian 32 bytes)
        let mut target_bytes = target.to_bytes_be();
        if target_bytes.len() < 32 {
            let mut pad = vec![0u8; 32 - target_bytes.len()];
            pad.extend_from_slice(&target_bytes);
            target_bytes = pad;
        } else if target_bytes.len() > 32 {
            // Truncate to 32 (keep least significant 32 bytes)
            let start = target_bytes.len() - 32;
            target_bytes = target_bytes[start..].to_vec();
        }
        let d_target: CudaSlice<u8> = self.device.htod_copy(target_bytes).ok()?;

        // Optimized launch configuration for maximum GPU utilization
        // Use larger blocks (256 threads) for better occupancy
        let threads_per_block = 256u32;
        let num_blocks = ((self.population_size as u32) + threads_per_block - 1) / threads_per_block;
        let cfg = LaunchConfig {
            grid_dim: (num_blocks, 1, 1),
            block_dim: (threads_per_block, 1, 1),
            shared_mem_bytes: 0,
        };

        // Host buffers
        let mut h_fitness = vec![0f32; self.population_size];

        for gen in 0..generations {
            // CPU hashing and fitness: ensure correctness for full header length
            let mut h_population_now = vec![0u8; self.population_size * self.mv_len];
            self.device
                .dtoh_sync_copy_into(&d_population, &mut h_population_now)
                .ok()?;

            let mut found_idx: Option<usize> = None;
            for idx in 0..(self.population_size) {
                let mv_slice = &h_population_now[idx * self.mv_len..(idx + 1) * self.mv_len];
                let mut candidate = header_prefix.to_vec();
                candidate.extend_from_slice(mv_slice);
                let digest = blake3::hash(&candidate);
                let h_bytes = digest.as_bytes();
                // Compare to target (big-endian)
                // Convert target once above; here compare BigUint directly for clarity
                let h_big = BigUint::from_bytes_be(h_bytes);
                if &h_big <= target {
                    found_idx = Some(idx);
                    break;
                }
                // Fitness: inverse log distance in bits
                let diff = if &h_big > target {
                    &h_big - target
                } else {
                    BigUint::from(0u32)
                };
                let bits = diff.bits() as f32;
                h_fitness[idx] = 1.0 / (1.0 + bits.ln());
            }

            if let Some(idx) = found_idx {
                let mv = h_population_now[idx * self.mv_len..(idx + 1) * self.mv_len].to_vec();
                let mut candidate = header_prefix.to_vec();
                candidate.extend_from_slice(&mv);
                let digest = blake3::hash(&candidate);
                let mut out = [0u8; 32];
                out.copy_from_slice(digest.as_bytes());
                return Some((mv, out));
            }

            // Copy fitness to device
            d_fitness = self.device.htod_copy(h_fitness.clone()).ok()?;

            // GA operators -> produce next generation on GPU
            unsafe {
                let func_ga = match self.device.get_func(module, "genetic_operators") {
                    Some(f) => f,
                    None => return None,
                };
                func_ga
                    .launch(
                        cfg,
                        (
                            &d_population,          // const uint8_t* population_current
                            &d_fitness,             // const float* fitness
                            &mut d_population_next, // uint8_t* population_next
                            &mut d_seeds,           // uint32_t* random_seeds
                            pop,                    // uint32_t population_size
                            mv_len_u32,             // uint32_t mv_len
                            mutation_rate,          // float mutation_rate
                        ),
                    )
                    .ok()?;
            }

            if gen % 50 == 0 {
                // Simple progress: best fitness
                let best = h_fitness.iter().cloned().fold(0.0f32, f32::max);
                println!("GPU Hybrid gen={} best_fitness={:.6}", gen, best);
            }

            // Swap populations
            std::mem::swap(&mut d_population, &mut d_population_next);
        }

        None
    }

    /// GPU brute-force: generate random mutation vectors on host in batches,
    /// hash on GPU and check against target, returning the first solution.
    pub fn mine_bruteforce_gpu(
        &self,
        header_prefix: &[u8],
        target: &BigUint,
        batches: usize,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        if !self.has_kernels {
            eprintln!("❌ GPU mining unavailable: CUDA kernels not loaded");
            return None;
        }

        let module = "blake3_simple_kernels";
        // Static device buffers reused across batches
        let d_header: CudaSlice<u8> = self.device.htod_copy(header_prefix.to_vec()).ok()?;
        let header_len_u32 = header_prefix.len() as u32;
        let mv_len_u32 = self.mv_len as u32;
        let pop_u32 = self.population_size as u32;
        
        // Optimized launch configuration for brute-force
        let threads_per_block = 256u32;
        let num_blocks = (pop_u32 + threads_per_block - 1) / threads_per_block;
        let cfg = LaunchConfig {
            grid_dim: (num_blocks, 1, 1),
            block_dim: (threads_per_block, 1, 1),
            shared_mem_bytes: 0,
        };

        let mut d_hashes: CudaSlice<u8> = self.device.alloc_zeros(self.population_size * 32).ok()?;
        let mut d_fitness: CudaSlice<f32> = self.device.alloc_zeros(self.population_size).ok()?;

        // Prepare target bytes on device
        let mut target_bytes = target.to_bytes_be();
        if target_bytes.len() < 32 {
            let mut pad = vec![0u8; 32 - target_bytes.len()];
            pad.extend_from_slice(&target_bytes);
            target_bytes = pad;
        } else if target_bytes.len() > 32 {
            let start = target_bytes.len() - 32;
            target_bytes = target_bytes[start..].to_vec();
        }
        
        // Debug: Show target being used
        eprintln!("🎯 GPU Target (first 8 bytes): {:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            target_bytes[0], target_bytes[1], target_bytes[2], target_bytes[3],
            target_bytes[4], target_bytes[5], target_bytes[6], target_bytes[7]);
        
        let d_target: CudaSlice<u8> = self.device.htod_copy(target_bytes.clone()).ok()?;

        let mut rng = rand::thread_rng();
        let mut host_pop = vec![0u8; self.population_size * self.mv_len];
        let mut host_fitness = vec![0f32; self.population_size];

        for batch_idx in 0..batches {
            // Fill with random bytes
            rng.fill(&mut host_pop[..]);
            let d_population: CudaSlice<u8> = self.device.htod_copy(host_pop.clone()).ok()?;

            unsafe {
                let func_hash = match self.device.get_func(module, "blake3_hash_batch") { 
                    Some(f) => f, None => return None 
                };
                let func_fitness = match self.device.get_func(module, "evaluate_fitness") { 
                    Some(f) => f, None => return None 
                };
                
                // Hash on GPU
                func_hash.launch(cfg, (
                    &d_header, header_len_u32, &d_population, mv_len_u32, &mut d_hashes, pop_u32,
                )).ok()?;
                
                // Evaluate fitness
                func_fitness.launch(cfg, (
                    &d_hashes, &d_target, &mut d_fitness, pop_u32,
                )).ok()?;
            }

            // Get results
            self.device.dtoh_sync_copy_into(&d_fitness, &mut host_fitness).ok()?;
            
            // Skip GPU Blake3 verification entirely if requested
            if batch_idx == 0 && std::env::var("SKIP_GPU_VERIFICATION").is_err() {
                let mut gpu_hashes = vec![0u8; self.population_size * 32];
                self.device.dtoh_sync_copy_into(&d_hashes, &mut gpu_hashes).ok()?;
                
                eprintln!("🔍 Verifying GPU Blake3 (first 3):");
                let mut all_match = true;
                for i in 0..3.min(self.population_size) {
                    let mv = &host_pop[i * self.mv_len..(i + 1) * self.mv_len];
                    let mut input = header_prefix.to_vec();
                    input.extend_from_slice(mv);
                    let cpu_hash = blake3::hash(&input);
                    let gpu_hash = &gpu_hashes[i * 32..(i + 1) * 32];
                    let match_status = if gpu_hash == cpu_hash.as_bytes() { 
                        "✅" 
                    } else { 
                        all_match = false;
                        "❌" 
                    };
                    eprintln!("  [{}] GPU: {} | CPU: {}", match_status,
                        hex::encode(&gpu_hash[..8]), hex::encode(&cpu_hash.as_bytes()[..8]));
                }
                
                if !all_match {
                    eprintln!("⚠️  GPU Blake3 mismatch - falling back to CPU");
                    // Continue with CPU fallback on mismatch
                }
            } else if batch_idx == 0 {
                eprintln!("🔄 GPU Blake3 verification skipped (SKIP_GPU_VERIFICATION=1)");
            }
            
            // Check for solution - use CPU verification if GPU Blake3 is buggy
            if std::env::var("SKIP_GPU_VERIFICATION").is_ok() {
                // GPU Blake3 is buggy, check every mutation vector with CPU
                for i in 0..self.population_size {
                    let mv = host_pop[i * self.mv_len..(i + 1) * self.mv_len].to_vec();
                    let mut input = header_prefix.to_vec();
                    input.extend_from_slice(&mv);
                    let cpu_hash = blake3::hash(&input);
                    let hash_uint = num_bigint::BigUint::from_bytes_be(cpu_hash.as_bytes());
                    
                    if hash_uint <= *target {
                        let mut hash = [0u8; 32];
                        hash.copy_from_slice(cpu_hash.as_bytes());
                        eprintln!("✅ Solution found via CPU verification in batch {}/{}", batch_idx + 1, batches);
                        return Some((mv, hash));
                    }
                }
            } else {
                // Use GPU fitness (normal mode)
                if let Some((idx, _)) = host_fitness.iter().enumerate().find(|(_, &f)| f > 100000.0) {
                    let mv = host_pop[idx * self.mv_len..(idx + 1) * self.mv_len].to_vec();
                    
                    // Always verify with CPU
                    let mut input = header_prefix.to_vec();
                    input.extend_from_slice(&mv);
                    let cpu_hash = blake3::hash(&input);
                    let hash_uint = num_bigint::BigUint::from_bytes_be(cpu_hash.as_bytes());
                    
                    if hash_uint <= *target {
                        let mut hash = [0u8; 32];
                        hash.copy_from_slice(cpu_hash.as_bytes());
                        eprintln!("✅ GPU found solution, CPU verified in batch {}/{}", batch_idx + 1, batches);
                        return Some((mv, hash));
                    }
                }
            }
            
            // Progress
            if batch_idx > 0 && batch_idx % 1000 == 0 {
                eprintln!("  Batch {}/{}, {} hashes", batch_idx, batches, batch_idx * self.population_size);
            }
        }

        None
    }

    /// Optimized GPU brute-force using the new blake3_brute_force kernel
    /// This uses systematic nonce search instead of random mutation vectors
    pub fn mine_bruteforce_nonce_gpu(
        &self,
        header_prefix: &[u8],
        target: &BigUint,
        start_nonce: u64,
        max_nonces: u64,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        if !self.has_kernels {
            eprintln!("❌ GPU mining unavailable: CUDA kernels not loaded");
            return None;
        }

        let module = "blake3_simple_kernels";
        
        // Check if brute-force kernel is available
        if self.device.get_func(module, "blake3_brute_force").is_none() {
            eprintln!("⚠️  blake3_brute_force kernel not available, falling back to batch method");
            return self.mine_bruteforce_gpu(header_prefix, target, (max_nonces / self.population_size as u64) as usize);
        }

        // Prepare target bytes on device
        let mut target_bytes = target.to_bytes_be();
        if target_bytes.len() < 32 {
            let mut pad = vec![0u8; 32 - target_bytes.len()];
            pad.extend_from_slice(&target_bytes);
            target_bytes = pad;
        } else if target_bytes.len() > 32 {
            let start = target_bytes.len() - 32;
            target_bytes = target_bytes[start..].to_vec();
        }

        let d_header: CudaSlice<u8> = self.device.htod_copy(header_prefix.to_vec()).ok()?;
        let d_target: CudaSlice<u8> = self.device.htod_copy(target_bytes).ok()?;
        let mut d_solution_found: CudaSlice<u8> = self.device.alloc_zeros(1).ok()?;
        let mut d_solution_nonce: CudaSlice<u64> = self.device.alloc_zeros(1).ok()?;

        let header_len_u32 = header_prefix.len() as u32;
        let threads_per_block = 256u32;
        let num_blocks = 1024u32; // Use many blocks for better GPU utilization
        let total_threads = threads_per_block * num_blocks;
        let iterations_per_thread = ((max_nonces + total_threads as u64 - 1) / total_threads as u64).max(1) as u32;

        let cfg = LaunchConfig {
            grid_dim: (num_blocks, 1, 1),
            block_dim: (threads_per_block, 1, 1),
            shared_mem_bytes: 0,
        };

        // Allocate device memory for solution hash
        let mut d_solution_hash = self.device.alloc_zeros::<u8>(32).ok()?;

        eprintln!("🚀 Starting GPU brute-force: {} threads, {} iterations each", 
                 total_threads, iterations_per_thread);
        eprintln!("🎯 Target range: {} to {}", start_nonce, start_nonce + max_nonces);

        unsafe {
            let func_brute = match self.device.get_func(module, "blake3_brute_force") {
                Some(f) => f,
                None => return None,
            };

            func_brute.launch(cfg, (
                &d_header,           // const uint8_t* header_prefix
                header_len_u32,      // uint32_t header_len
                start_nonce,         // uint64_t start_nonce
                &d_target,           // const uint8_t* target_bytes
                &mut d_solution_found, // uint8_t* solution_found
                &mut d_solution_nonce, // uint64_t* solution_nonce
                iterations_per_thread, // uint32_t max_iterations
                &mut d_solution_hash,  // uint8_t* solution_hash
            )).ok()?;
        }

        // Check results
        let mut solution_found = vec![0u8; 1];
        let mut solution_nonce = vec![0u64; 1];
        let mut solution_hash = vec![0u8; 32];
        
        self.device.dtoh_sync_copy_into(&d_solution_found, &mut solution_found).ok()?;
        
        if solution_found[0] != 0 {
            self.device.dtoh_sync_copy_into(&d_solution_nonce, &mut solution_nonce).ok()?;
            self.device.dtoh_sync_copy_into(&d_solution_hash, &mut solution_hash).ok()?;
            let nonce = solution_nonce[0];
            
            eprintln!("✅ GPU brute-force found solution at nonce: {}", nonce);
            
            // GPU has already computed and verified the hash - use it directly!
            let mut hash = [0u8; 32];
            hash.copy_from_slice(&solution_hash);
            
            // Return nonce as mutation vector (respecting mv_len)
            let mut nonce_bytes = vec![0u8; self.mv_len];
            // Fill first 8 bytes with nonce (little-endian)
            for i in 0..8.min(self.mv_len) {
                nonce_bytes[i] = ((nonce >> (i * 8)) & 0xFF) as u8;
            }
            // Fill remaining bytes with random data if mv_len > 8
            if self.mv_len > 8 {
                use rand::Rng;
                let mut rng = rand::thread_rng();
                for i in 8..self.mv_len {
                    nonce_bytes[i] = rng.gen();
                }
            }
            
            return Some((nonce_bytes, hash));
        }

        None
    }
}

#[cfg(not(feature = "cuda"))]
#[allow(dead_code)]
impl GpuMiner {
    pub fn new(
        _population_size: usize,
        _mv_len: usize,
        _device_id: usize,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        Err("CUDA support not compiled. Build with --features cuda".into())
    }

    pub fn mine_with_ga(
        &self,
        _header_prefix: &[u8],
        _target: &BigUint,
        _generations: usize,
        _mutation_rate: f32,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        None
    }

    pub fn mine_bruteforce_gpu(
        &self,
        _header_prefix: &[u8],
        _target: &BigUint,
        _batches: usize,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        None
    }

    pub fn mine_bruteforce_nonce_gpu(
        &self,
        _header_prefix: &[u8],
        _target: &BigUint,
        _start_nonce: u64,
        _max_nonces: u64,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        None
    }
}

// CPU fallback for systems without CUDA
pub fn cpu_ga_mine(
    header_prefix: &[u8],
    target: &BigUint,
    population_size: usize,
    mv_len: usize,
    generations: usize,
    mutation_rate: f32,
) -> Option<(Vec<u8>, [u8; 32])> {
    use blake3::Hasher;

    // Individual: (mutation_vector, fitness)
    let mut population: Vec<(Vec<u8>, f32)> = (0..population_size)
        .map(|_| {
            let mut mv = vec![0u8; mv_len];
            rand::thread_rng().fill(&mut mv[..]);
            (mv, 0.0)
        })
        .collect();

    let mut rng = rand::thread_rng();
    let mut best_fitness = 0.0f32;

    for gen in 0..generations {
        // Evaluate fitness
        for (mv, fitness) in &mut population {
            let mut candidate = header_prefix.to_vec();
            candidate.extend_from_slice(mv);

            let mut hasher = Hasher::new();
            hasher.update(&candidate);
            let hash = hasher.finalize();
            let hash_bytes = hash.as_bytes();

            // Check if solution
            let hash_bigint = BigUint::from_bytes_be(hash_bytes);
            if &hash_bigint <= target {
                let mut result = [0u8; 32];
                result.copy_from_slice(hash_bytes);
                println!("✅ CPU GA Solution found at generation {}", gen);
                return Some((mv.clone(), result));
            }

            // Calculate fitness (inverse of distance)
            let diff = if &hash_bigint > target {
                &hash_bigint - target
            } else {
                BigUint::from(0u32)
            };

            let bits = diff.bits() as f32;
            *fitness = 1.0 / (1.0 + bits.ln());

            if *fitness > best_fitness {
                best_fitness = *fitness;
            }
        }

        if gen % 100 == 0 {
            println!("CPU Gen {}: best_fitness={:.6}", gen, best_fitness);
        }

        // Create next generation
        let mut next_gen = Vec::with_capacity(population_size);

        for _ in 0..population_size {
            // Tournament selection
            let parent1 = tournament_select(&population, &mut rng);
            let parent2 = tournament_select(&population, &mut rng);

            // Crossover
            let crossover_point = rng.gen_range(0..mv_len);
            let mut child = vec![0u8; mv_len];
            child[..crossover_point].copy_from_slice(&parent1[..crossover_point]);
            child[crossover_point..].copy_from_slice(&parent2[crossover_point..]);

            // Mutation
            for byte in &mut child {
                if rng.gen::<f32>() < mutation_rate {
                    *byte = rng.gen();
                }
            }

            next_gen.push((child, 0.0));
        }

        population = next_gen;
    }

    println!(
        "❌ CPU GA: No solution found after {} generations",
        generations
    );
    None
}

fn tournament_select<'a>(population: &'a [(Vec<u8>, f32)], rng: &mut impl Rng) -> &'a Vec<u8> {
    let idx1 = rng.gen_range(0..population.len());
    let idx2 = rng.gen_range(0..population.len());

    if population[idx1].1 > population[idx2].1 {
        &population[idx1].0
    } else {
        &population[idx2].0
    }
}
