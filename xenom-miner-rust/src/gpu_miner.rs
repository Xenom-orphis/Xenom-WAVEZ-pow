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
    pub fn new(population_size: usize, mv_len: usize) -> Result<Self, Box<dyn std::error::Error>> {
        // Initialize CUDA device
        let device = CudaDevice::new(0)?;

        // Try to load compiled PTX from env (set by build.rs)
        let mut has_kernels = false;
        if let Ok(ptx_path) = std::env::var("CUDA_BLAKE3_PTX") {
            let ptx = std::fs::read_to_string(&ptx_path)?;
            // Load module with our three kernels
            // Module name must be unique per device
            let module_name = "blake3_kernels";
            // Ignore error if already loaded
            let _ = device.load_ptx(
                ptx.into(),
                module_name,
                &["blake3_hash_batch", "evaluate_fitness", "genetic_operators"],
            );
            has_kernels = device.get_func(module_name, "blake3_hash_batch").is_some()
                && device.get_func(module_name, "evaluate_fitness").is_some()
                && device.get_func(module_name, "genetic_operators").is_some();
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

        let module = "blake3_kernels";

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
        let mut h_seeds: Vec<u32> = (0..self.population_size).map(|_| rng.gen()).collect();
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

        // Launch configuration
        let cfg = LaunchConfig::for_num_elems(self.population_size as u32);

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
                let mut meets = true;
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
}

#[cfg(not(feature = "cuda"))]
#[allow(dead_code)]
impl GpuMiner {
    pub fn new(
        _population_size: usize,
        _mv_len: usize,
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

    /// GPU brute-force: generate random mutation vectors on host in batches,
    /// hash and check on GPU, return first solution.
    pub fn mine_bruteforce_gpu(
        &self,
        header_prefix: &[u8],
        target: &BigUint,
        batches: usize,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        if !self.has_kernels {
            return None;
        }

        let module = "blake3_kernels";
        let func_hash = match self.device.get_func(module, "blake3_hash_batch") {
            Some(f) => f,
            None => return None,
        };
        let func_fitness = match self.device.get_func(module, "evaluate_fitness") {
            Some(f) => f,
            None => return None,
        };

        // Static device buffers reused across batches
        let d_header: CudaSlice<u8> = self.device.htod_copy(header_prefix.to_vec()).ok()?;
        let header_len_u32 = header_prefix.len() as u32;
        let mv_len_u32 = self.mv_len as u32;
        let pop_u32 = self.population_size as u32;
        let cfg = LaunchConfig::for_num_elems(pop_u32);

        let mut d_population: CudaSlice<u8> = self
            .device
            .alloc_zeros(self.population_size * self.mv_len)
            .ok()?;
        let mut d_hashes: CudaSlice<u8> =
            self.device.alloc_zeros(self.population_size * 32).ok()?;
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
        let d_target: CudaSlice<u8> = self.device.htod_copy(target_bytes).ok()?;

        let mut rng = rand::thread_rng();
        let mut host_pop = vec![0u8; self.population_size * self.mv_len];
        let mut host_fitness = vec![0f32; self.population_size];

        for _ in 0..batches {
            // Fill with random bytes
            rng.fill(&mut host_pop[..]);
            d_population = self.device.htod_copy(host_pop.clone()).ok()?;

            unsafe {
                func_hash
                    .launch(
                        cfg,
                        (
                            &d_header,
                            header_len_u32,
                            &d_population,
                            mv_len_u32,
                            &mut d_hashes,
                            pop_u32,
                        ),
                    )
                    .ok()?;
                func_fitness
                    .launch(cfg, (&d_hashes, &d_target, &mut d_fitness, pop_u32))
                    .ok()?;
            }

            // Pull fitness and check for solution
            self.device
                .dtoh_sync_copy_into(&d_fitness, &mut host_fitness)
                .ok()?;
            if let Some((idx, _)) = host_fitness.iter().enumerate().find(|(_, &f)| f >= 1.0) {
                let mv = host_pop[idx * self.mv_len..(idx + 1) * self.mv_len].to_vec();
                let mut candidate = header_prefix.to_vec();
                candidate.extend_from_slice(&mv);
                let digest = blake3::hash(&candidate);
                let mut out = [0u8; 32];
                out.copy_from_slice(digest.as_bytes());
                return Some((mv, out));
            }
        }

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
