#[cfg(feature = "cuda")]
use cudarc::driver::*;
#[cfg(feature = "cuda")]
use std::sync::Arc;
use num_bigint::BigUint;
use rand::Rng;

#[allow(dead_code)]
pub struct GpuMiner {
    #[cfg(feature = "cuda")]
    device: Arc<CudaDevice>,
    #[cfg(feature = "cuda")]
    module: CudaModule,
    population_size: usize,
    mv_len: usize,
}

#[cfg(feature = "cuda")]
impl GpuMiner {
    pub fn new(population_size: usize, mv_len: usize) -> Result<Self, Box<dyn std::error::Error>> {
        // Initialize CUDA device
        let device = CudaDevice::new(0)?;
        
        // Load PTX from compiled CUDA kernel
        let ptx = include_str!(concat!(env!("OUT_DIR"), "/blake3.ptx"));
        let module = device.load_ptx(ptx.into(), "blake3", &["blake3_hash_batch", "evaluate_fitness", "genetic_operators"])?;
        
        Ok(Self {
            device,
            module,
            population_size,
            mv_len,
        })
    }
    
    pub fn mine_with_ga(
        &self,
        header_prefix: &[u8],
        target: &BigUint,
        generations: usize,
        mutation_rate: f32,
    ) -> Option<(Vec<u8>, [u8; 32])> {
        let dev = &self.device;
        
        // Convert target to bytes (big-endian)
        let target_bytes = target.to_bytes_be();
        let mut target_padded = vec![0u8; 32];
        let offset = 32 - target_bytes.len().min(32);
        target_padded[offset..].copy_from_slice(&target_bytes[..target_bytes.len().min(32)]);
        
        // Allocate GPU memory
        let d_header = dev.htod_copy(header_prefix.to_vec()).unwrap();
        let d_target = dev.htod_copy(target_padded.clone()).unwrap();
        
        // Initialize population randomly on CPU
        let mut population = vec![0u8; self.population_size * self.mv_len];
        let mut rng = rand::thread_rng();
        rng.fill(&mut population[..]);
        
        let mut d_population_current = dev.htod_copy(population.clone()).unwrap();
        let mut d_population_next = dev.alloc_zeros::<u8>(self.population_size * self.mv_len).unwrap();
        let mut d_hashes = dev.alloc_zeros::<u8>(self.population_size * 32).unwrap();
        let mut d_fitness = dev.alloc_zeros::<f32>(self.population_size).unwrap();
        
        // Random seeds for genetic operators
        let mut seeds: Vec<u32> = (0..self.population_size).map(|_| rng.gen()).collect();
        let mut d_seeds = dev.htod_copy(seeds.clone()).unwrap();
        
        let threads_per_block = 256;
        let blocks = (self.population_size + threads_per_block - 1) / threads_per_block;
        let cfg = LaunchConfig {
            grid_dim: (blocks as u32, 1, 1),
            block_dim: (threads_per_block as u32, 1, 1),
            shared_mem_bytes: 0,
        };
        
        // Get kernel functions
        let hash_kernel = self.module.get_func("blake3_hash_batch").unwrap();
        let fitness_kernel = self.module.get_func("evaluate_fitness").unwrap();
        let ga_kernel = self.module.get_func("genetic_operators").unwrap();
        
        let mut best_fitness = 0.0f32;
        let mut best_mv = vec![0u8; self.mv_len];
        
        for gen in 0..generations {
            // 1. Hash all individuals
            unsafe {
                hash_kernel.launch(
                    cfg,
                    (
                        &d_header,
                        header_prefix.len() as u32,
                        &d_population_current,
                        self.mv_len as u32,
                        &d_hashes,
                        self.population_size as u32,
                    ),
                ).unwrap();
            }
            
            // 2. Evaluate fitness
            unsafe {
                fitness_kernel.launch(
                    cfg,
                    (
                        &d_hashes,
                        &d_target,
                        &d_fitness,
                        self.population_size as u32,
                    ),
                ).unwrap();
            }
            
            // 3. Copy fitness back to check for solution
            let fitness_cpu = dev.dtoh_sync_copy(&d_fitness).unwrap();
            
            // Check if we found a solution
            for (i, &fit) in fitness_cpu.iter().enumerate() {
                if fit >= 1.0 {
                    // Solution found! Copy back the mutation vector and hash
                    let pop_cpu = dev.dtoh_sync_copy(&d_population_current).unwrap();
                    let hashes_cpu = dev.dtoh_sync_copy(&d_hashes).unwrap();
                    
                    let mv_start = i * self.mv_len;
                    let mv = pop_cpu[mv_start..mv_start + self.mv_len].to_vec();
                    
                    let hash_start = i * 32;
                    let mut hash = [0u8; 32];
                    hash.copy_from_slice(&hashes_cpu[hash_start..hash_start + 32]);
                    
                    println!("✅ GPU Solution found at generation {}", gen);
                    return Some((mv, hash));
                }
                
                if fit > best_fitness {
                    best_fitness = fit;
                    let pop_cpu = dev.dtoh_sync_copy(&d_population_current).unwrap();
                    let mv_start = i * self.mv_len;
                    best_mv.copy_from_slice(&pop_cpu[mv_start..mv_start + self.mv_len]);
                }
            }
            
            // Progress report every 100 generations
            if gen % 100 == 0 {
                println!("Gen {}: best_fitness={:.6}", gen, best_fitness);
            }
            
            // 4. Apply genetic operators (selection, crossover, mutation)
            unsafe {
                ga_kernel.launch(
                    cfg,
                    (
                        &d_population_current,
                        &d_fitness,
                        &d_population_next,
                        &d_seeds,
                        self.population_size as u32,
                        self.mv_len as u32,
                        mutation_rate,
                    ),
                ).unwrap();
            }
            
            // Swap populations
            std::mem::swap(&mut d_population_current, &mut d_population_next);
        }
        
        println!("❌ GPU: No solution found after {} generations (best fitness: {:.6})", 
                 generations, best_fitness);
        None
    }
}

#[cfg(not(feature = "cuda"))]
#[allow(dead_code)]
impl GpuMiner {
    pub fn new(_population_size: usize, _mv_len: usize) -> Result<Self, Box<dyn std::error::Error>> {
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
    
    println!("❌ CPU GA: No solution found after {} generations", generations);
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
