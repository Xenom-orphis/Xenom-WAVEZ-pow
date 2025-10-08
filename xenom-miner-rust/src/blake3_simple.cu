// Optimized Blake3 CUDA implementation for mining
// Based on official Blake3 specification with mining-specific optimizations

#include <cuda_runtime.h>
#include <stdint.h>

// Blake3 constants
#define BLAKE3_OUT_LEN 32
#define BLAKE3_BLOCK_LEN 64
#define BLAKE3_CHUNK_LEN 1024

// Blake3 IV (same as SHA-256)
__constant__ uint32_t IV[8] = {
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
};

// Blake3 message permutation schedule
__constant__ uint8_t MSG_SCHEDULE[7][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8},
    {3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1},
    {10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6},
    {12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4},
    {9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7},
    {11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13},
};

// Blake3 flags
#define CHUNK_START (1 << 0)
#define CHUNK_END (1 << 1)
#define PARENT (1 << 2)
#define ROOT (1 << 3)
#define KEYED_HASH (1 << 4)
#define DERIVE_KEY_CONTEXT (1 << 5)
#define DERIVE_KEY_MATERIAL (1 << 6)

__device__ __forceinline__ uint32_t rotr32(uint32_t w, uint32_t c) {
    return (w >> c) | (w << (32 - c));
}

// Blake3 G function - core mixing function
__device__ __forceinline__ void g(uint32_t *state, uint32_t a, uint32_t b, uint32_t c, uint32_t d,
                                  uint32_t mx, uint32_t my) {
    state[a] = state[a] + state[b] + mx;
    state[d] = rotr32(state[d] ^ state[a], 16);
    state[c] = state[c] + state[d];
    state[b] = rotr32(state[b] ^ state[c], 12);
    state[a] = state[a] + state[b] + my;
    state[d] = rotr32(state[d] ^ state[a], 8);
    state[c] = state[c] + state[d];
    state[b] = rotr32(state[b] ^ state[c], 7);
}

// Blake3 round function - applies G function in column and diagonal pattern
__device__ __forceinline__ void round_fn(uint32_t *state, const uint32_t *msg, const uint8_t *schedule) {
    // Columns
    g(state, 0, 4, 8, 12, msg[schedule[0]], msg[schedule[1]]);
    g(state, 1, 5, 9, 13, msg[schedule[2]], msg[schedule[3]]);
    g(state, 2, 6, 10, 14, msg[schedule[4]], msg[schedule[5]]);
    g(state, 3, 7, 11, 15, msg[schedule[6]], msg[schedule[7]]);
    // Diagonals
    g(state, 0, 5, 10, 15, msg[schedule[8]], msg[schedule[9]]);
    g(state, 1, 6, 11, 12, msg[schedule[10]], msg[schedule[11]]);
    g(state, 2, 7, 8, 13, msg[schedule[12]], msg[schedule[13]]);
    g(state, 3, 4, 9, 14, msg[schedule[14]], msg[schedule[15]]);
}

// Blake3 compression function
__device__ void blake3_compress(const uint32_t cv[8], const uint8_t block[64],
                               uint8_t block_len, uint64_t counter, uint8_t flags,
                               uint32_t out[16]) {
    uint32_t state[16];
    uint32_t block_words[16];
    
    // Initialize state with chaining value and IV
    for (int i = 0; i < 8; i++) {
        state[i] = cv[i];
        state[i + 8] = IV[i];
    }
    
    // Set counter, block length, and flags
    state[12] = (uint32_t)counter;
    state[13] = (uint32_t)(counter >> 32);
    state[14] = (uint32_t)block_len;
    state[15] = (uint32_t)flags;
    
    // Load message words (little-endian)
    for (int i = 0; i < 16; i++) {
        block_words[i] = ((uint32_t)block[i * 4 + 0]) |
                        ((uint32_t)block[i * 4 + 1] << 8) |
                        ((uint32_t)block[i * 4 + 2] << 16) |
                        ((uint32_t)block[i * 4 + 3] << 24);
    }
    
    // 7 rounds of mixing
    for (int i = 0; i < 7; i++) {
        round_fn(state, block_words, MSG_SCHEDULE[i]);
    }
    
    // Finalize: XOR the two halves
    for (int i = 0; i < 8; i++) {
        state[i] ^= state[i + 8];
        state[i + 8] ^= cv[i];
    }
    
    // Copy to output
    for (int i = 0; i < 16; i++) {
        out[i] = state[i];
    }
}

// Optimized Blake3 hash function for mining (handles variable-length inputs)
__device__ void blake3_hash_optimized(const uint8_t *input, uint32_t input_len, uint8_t *output) {
    uint32_t cv[8];
    
    // Initialize chaining value with IV
    for (int i = 0; i < 8; i++) {
        cv[i] = IV[i];
    }
    
    uint32_t offset = 0;
    uint64_t chunk_counter = 0;
    
    // Process input in 64-byte blocks
    while (offset < input_len) {
        uint8_t block[64];
        uint32_t block_len = (input_len - offset < 64) ? (input_len - offset) : 64;
        
        // Copy input to block buffer
        for (uint32_t i = 0; i < block_len; i++) {
            block[i] = input[offset + i];
        }
        // Zero-pad remaining bytes
        for (uint32_t i = block_len; i < 64; i++) {
            block[i] = 0;
        }
        
        // Determine flags
        uint8_t flags = 0;
        if (chunk_counter == 0) flags |= CHUNK_START;
        if (offset + block_len >= input_len) flags |= CHUNK_END | ROOT;
        
        // Compress block
        uint32_t out[16];
        blake3_compress(cv, block, (uint8_t)block_len, chunk_counter, flags, out);
        
        // Update chaining value with first 8 words
        for (int i = 0; i < 8; i++) {
            cv[i] = out[i];
        }
        
        offset += block_len;
        if (offset < input_len) chunk_counter++;
    }
    
    // Extract final hash (little-endian)
    for (int i = 0; i < 8; i++) {
        output[i * 4 + 0] = (uint8_t)(cv[i] & 0xFF);
        output[i * 4 + 1] = (uint8_t)((cv[i] >> 8) & 0xFF);
        output[i * 4 + 2] = (uint8_t)((cv[i] >> 16) & 0xFF);
        output[i * 4 + 3] = (uint8_t)((cv[i] >> 24) & 0xFF);
    }
}

// Fast single-block Blake3 for small inputs (≤64 bytes) - common in mining
__device__ __forceinline__ void blake3_hash_single_block(const uint8_t *input, uint32_t len, uint8_t *output) {
    uint32_t cv[8];
    uint8_t block[64] = {0};
    
    // Initialize CV with IV
    for (int i = 0; i < 8; i++) {
        cv[i] = IV[i];
    }
    
    // Copy input to block
    for (uint32_t i = 0; i < len && i < 64; i++) {
        block[i] = input[i];
    }
    
    // Single compression with appropriate flags
    uint32_t out[16];
    blake3_compress(cv, block, (uint8_t)len, 0, CHUNK_START | CHUNK_END | ROOT, out);
    
    // Extract hash (little-endian)
    for (int i = 0; i < 8; i++) {
        output[i * 4 + 0] = (uint8_t)(out[i] & 0xFF);
        output[i * 4 + 1] = (uint8_t)((out[i] >> 8) & 0xFF);
        output[i * 4 + 2] = (uint8_t)((out[i] >> 16) & 0xFF);
        output[i * 4 + 3] = (uint8_t)((out[i] >> 24) & 0xFF);
    }
}

// Optimized Blake3 batch hashing kernel for mining
extern "C" __global__ void blake3_hash_batch(
    const uint8_t *header_prefix,
    uint32_t header_len,
    const uint8_t *mutation_vectors,
    uint32_t mv_len,
    uint8_t *hashes,
    uint32_t population_size
) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= population_size) return;
    
    // Use shared memory for better performance
    __shared__ uint8_t shared_header[256];
    
    // Cooperatively load header to shared memory
    if (threadIdx.x < header_len) {
        shared_header[threadIdx.x] = header_prefix[threadIdx.x];
    }
    __syncthreads();
    
    // Build full input in local memory
    uint8_t buffer[512]; // Increased buffer size for larger inputs
    uint32_t total_len = header_len + mv_len;
    
    // Copy header from shared memory
    for (uint32_t i = 0; i < header_len && i < 512; i++) {
        buffer[i] = (i < 256) ? shared_header[i] : header_prefix[i];
    }
    
    // Copy mutation vector for this thread
    const uint8_t *mv = mutation_vectors + (idx * mv_len);
    for (uint32_t i = 0; i < mv_len && (header_len + i) < 512; i++) {
        buffer[header_len + i] = mv[i];
    }
    
    // Compute Blake3 hash
    uint8_t *hash_out = hashes + (idx * 32);
    
    if (total_len <= 64) {
        // Fast path for small inputs (most mining cases)
        blake3_hash_single_block(buffer, total_len, hash_out);
    } else {
        // General path for larger inputs
        blake3_hash_optimized(buffer, total_len, hash_out);
    }
}

// Optimized fitness evaluation kernel with early termination
extern "C" __global__ void evaluate_fitness(
    const uint8_t *hashes,
    const uint8_t *target_bytes,
    float *fitness,
    uint32_t population_size
) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= population_size) return;
    
    const uint8_t *hash = hashes + (idx * 32);
    
    // Load target to shared memory for faster access
    __shared__ uint8_t shared_target[32];
    if (threadIdx.x < 32) {
        shared_target[threadIdx.x] = target_bytes[threadIdx.x];
    }
    __syncthreads();
    
    // Compare hash to target (big-endian comparison)
    bool meets_target = true;
    int first_diff_pos = 32;
    
    for (int k = 0; k < 32; k++) {
        uint8_t h = hash[k];
        uint8_t t = shared_target[k];
        
        if (h < t) {
            // hash < target, solution found
            break;
        } else if (h > t) {
            meets_target = false;
            first_diff_pos = k;
            break;
        }
    }
    
    if (meets_target) {
        // Solution found - use maximum fitness
        fitness[idx] = 999999.0f;
        return;
    }
    
    // Calculate weighted distance for genetic algorithm
    float weighted_dist = 0.0f;
    for (int k = 0; k < 32; k++) {
        int diff = (int)hash[k] - (int)shared_target[k];
        // Weight earlier bytes more heavily (big-endian)
        float weight = (32.0f - k) / 32.0f;
        weighted_dist += diff * weight;
    }
    
    // Inverse fitness with better scaling
    fitness[idx] = 1.0f / (1.0f + fabsf(weighted_dist) / 1000.0f);
}

// Optimized genetic operators kernel for evolutionary mining
extern "C" __global__ void genetic_operators(
    const uint8_t *population_current,
    const float *fitness,
    uint8_t *population_next,
    uint32_t *random_seeds,
    uint32_t population_size,
    uint32_t mv_len,
    float mutation_rate
) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= population_size) return;
    
    // Fast LCG random number generator
    uint32_t seed = random_seeds[idx];
    
    auto next_rand = [&seed]() -> uint32_t {
        seed = seed * 1664525u + 1013904223u;
        return seed;
    };
    
    // Tournament selection with size 3 for better selection pressure
    uint32_t best_idx = 0;
    float best_fitness = -1.0f;
    
    for (int tournament = 0; tournament < 3; tournament++) {
        uint32_t candidate = next_rand() % population_size;
        if (fitness[candidate] > best_fitness) {
            best_fitness = fitness[candidate];
            best_idx = candidate;
        }
    }
    
    // Select second parent
    uint32_t parent2_idx = 0;
    float parent2_fitness = -1.0f;
    
    for (int tournament = 0; tournament < 3; tournament++) {
        uint32_t candidate = next_rand() % population_size;
        if (fitness[candidate] > parent2_fitness && candidate != best_idx) {
            parent2_fitness = fitness[candidate];
            parent2_idx = candidate;
        }
    }
    
    const uint8_t *parent1 = population_current + (best_idx * mv_len);
    const uint8_t *parent2 = population_current + (parent2_idx * mv_len);
    uint8_t *child = population_next + (idx * mv_len);
    
    // Uniform crossover (better mixing than single-point)
    for (uint32_t i = 0; i < mv_len; i++) {
        child[i] = (next_rand() & 1) ? parent1[i] : parent2[i];
    }
    
    // Adaptive mutation based on fitness
    float adaptive_rate = mutation_rate;
    if (best_fitness < 0.1f) {
        adaptive_rate *= 2.0f; // Increase mutation when stuck
    }
    
    // Bit-flip mutation
    for (uint32_t i = 0; i < mv_len; i++) {
        if ((next_rand() % 10000) < (uint32_t)(adaptive_rate * 10000)) {
            // Flip a random bit instead of replacing entire byte
            uint32_t bit_pos = next_rand() % 8;
            child[i] ^= (1 << bit_pos);
        }
    }
    
    // Update random seed
    random_seeds[idx] = seed;
}

// Brute-force kernel for systematic nonce search
extern "C" __global__ void blake3_brute_force(
    const uint8_t *header_prefix,
    uint32_t header_len,
    uint64_t start_nonce,
    const uint8_t *target_bytes,
    uint8_t *solution_found,
    uint64_t *solution_nonce,
    uint32_t max_iterations,
    uint8_t *solution_hash
) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    uint64_t nonce = start_nonce + idx;
    
    uint8_t buffer[128];
    uint8_t hash[32];
    
    for (uint32_t iter = 0; iter < max_iterations && !(*solution_found); iter++) {
        // Build input: header + nonce (little-endian)
        for (uint32_t i = 0; i < header_len; i++) {
            buffer[i] = header_prefix[i];
        }
        
        // Append nonce as 8 bytes (little-endian)
        for (int i = 0; i < 8; i++) {
            buffer[header_len + i] = (uint8_t)((nonce >> (i * 8)) & 0xFF);
        }
        
        // Hash the input
        uint32_t total_len = header_len + 8;
        if (total_len <= 64) {
            blake3_hash_single_block(buffer, total_len, hash);
        } else {
            blake3_hash_optimized(buffer, total_len, hash);
        }
        
        // Check if hash meets target (hash <= target)
        // Compare as big-endian: most significant byte first
        bool meets_target = true;
        for (int k = 0; k < 32; k++) {
            if (hash[k] < target_bytes[k]) {
                meets_target = true;  // hash < target, definitely valid
                break;
            } else if (hash[k] > target_bytes[k]) {
                meets_target = false; // hash > target, invalid
                break;
            }
            // If equal, continue to next byte
        }
        // If all bytes equal, hash == target, which is valid (meets_target stays true)
        
        if (meets_target) {
            // Atomic update to prevent race conditions
            if (atomicCAS((unsigned int*)solution_found, 0, 1) == 0) {
                *solution_nonce = nonce;
                // Copy hash to output
                for (int i = 0; i < 32; i++) {
                    solution_hash[i] = hash[i];
                }
            }
            return;
        }
        
        nonce += blockDim.x * gridDim.x; // Stride by total thread count
    }
}
