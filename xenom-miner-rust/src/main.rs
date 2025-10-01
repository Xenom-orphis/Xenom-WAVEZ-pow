use blake3::Hasher;
use clap::Parser;
use rand::prelude::*;
use rayon::prelude::*;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

/// Rust で実装された最適化マイナー。並列 GA（CPU）に対応し、GPU/OpenCL 統合用のフックを備える
#[derive(Parser, Debug)]
#[command(author, version, about = "Xenom optimized miner (Rust) - BLAKE3 + GA", long_about = None)]
struct Args {
    /// ヘッダバイトの 16 進文字列（`BlockHeader.bytes()` のシリアライズ形式に準拠）
    #[arg(short, long)]
    header_hex: String,

    /// difficulty bits（compact uint32）の 16 進表記。例: 1f00ffff
    #[arg(short, long)]
    bits_hex: String,

    /// mutation vector のバイト長
    #[arg(short = 'm', long, default_value_t = 16usize)]
    mv_len: usize,

    /// 個体数（ワーカーごと）
    #[arg(short = 'p', long, default_value_t = 512usize)]
    population: usize,

    /// 最大世代数
    #[arg(short = 'g', long, default_value_t = 10000usize)]
    generations: usize,

    /// 使用するスレッド数（rayon）。0 = 自動
    #[arg(short = 't', long, default_value_t = 0usize)]
    threads: usize,

    /// GA を使わず CPU ブルートフォースのみ
    #[arg(long, default_value_t = false)]
    brute: bool,
}

fn hex_to_bytes(s: &str) -> Vec<u8> {
    hex::decode(s).expect("invalid hex")
}

fn compact_bits_to_target(bits: u32) -> num_bigint::BigUint {
    // Scala 実装と同様: bits = (exp << 24) | coeff(3 バイト)
    let exponent = (bits >> 24) as i32;
    let coefficient = bits & 0x00ffffff;
    let coeff = num_bigint::BigUint::from(coefficient as u64);
    let base = num_bigint::BigUint::from(256u32);
    if exponent - 3 >= 0 {
        coeff * base.pow((exponent - 3) as u32)
    } else {
        coeff / base.pow((3 - exponent) as u32)
    }
}

fn blake3_hash(input: &[u8]) -> [u8; 32] {
    let mut hasher = Hasher::new();
    hasher.update(input);
    let out = hasher.finalize();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(out.as_bytes());
    arr
}

fn hash_to_biguint(hash: &[u8]) -> num_bigint::BigUint {
    num_bigint::BigUint::from_bytes_be(hash)
}

// 目的値（target）の BigUint と比較可能な適応度へ変換。ハッシュが小さいほど良い。
fn fitness_from_hash_biguint(hash: &[u8], target: &num_bigint::BigUint) -> f64 {
    // 適応度は [0,1]。hash <= target なら 1 に近づく
    let h = hash_to_biguint(hash);
    if &h <= target {
        1.0
    } else {
        // 対数的な距離を (0,1) に写像
        let diff = &h - target;
        // スケールした逆数: 1/(1+log(bits)) を利用
        let bits = (diff.bits() as f64).max(1.0);
        1.0 / (1.0 + bits.ln())
    }
}

fn parse_bits_hex(s: &str) -> u32 {
    u32::from_str_radix(s, 16).expect("invalid bits hex")
}

fn run_bruteforce(header_prefix: Arc<Vec<u8>>, bits: &num_bigint::BigUint, mv_len: usize) {
    let found = Arc::new(AtomicBool::new(false));
    let attempts = Arc::new(AtomicU64::new(0));
    let start = Instant::now();
    let threads = num_cpus::get();

    rayon::ThreadPoolBuilder::new()
        .num_threads(threads)
        .build_global()
        .unwrap();

    (0..threads).into_par_iter().for_each(|tid| {
        let mut rng = rand::thread_rng();
        let mut local_nonce: u64 = tid as u64;
        while !found.load(Ordering::Relaxed) {
            let mut mv = vec![0u8; mv_len];
            rng.fill_bytes(&mut mv);
            // ヘッダ組み立て: header_prefix + mv（header_prefix は mutationVector を含まない部分）
            let mut candidate = header_prefix.as_ref().clone();
            candidate.extend_from_slice(&mv);
            let digest = blake3_hash(&candidate);
            let ok = hash_to_biguint(&digest) <= *bits;
            let tot = attempts.fetch_add(1, Ordering::Relaxed) + 1;
            if ok {
                if !found.swap(true, Ordering::SeqCst) {
                    let elapsed = start.elapsed();
                    println!(
                        "FOUND! tid={} nonce={} mv={} digest={} attempts={} time={:?}",
                        tid,
                        local_nonce,
                        hex::encode(&mv),
                        hex::encode(digest),
                        tot,
                        elapsed
                    );
                }
                break;
            }
            if tot % 1_000_000 == 0 {
                let elapsed = start.elapsed();
                println!(
                    "attempts={} time={:?} rate={} H/s",
                    tot,
                    elapsed,
                    tot as f64 / elapsed.as_secs_f64()
                );
            }
            local_nonce = local_nonce.wrapping_add(threads as u64);
        }
    });
}

fn run_ga(
    header_prefix: Arc<Vec<u8>>,
    bits: &num_bigint::BigUint,
    mv_len: usize,
    population: usize,
    generations: usize,
) {
    // 個体群: mutation vector の Vec<Vec<u8>>
    let mut rng = rand::thread_rng();
    let mut population_vec: Vec<Vec<u8>> = (0..population)
        .map(|_| {
            let mut v = vec![0u8; mv_len];
            rng.fill_bytes(&mut v);
            v
        })
        .collect();

    let start = Instant::now();
    let target = bits.clone();

    for gen in 0..generations {
        // 適応度の並列評価
        let fitness: Vec<f64> = population_vec
            .par_iter()
            .map(|mv| {
                let mut candidate = header_prefix.as_ref().clone();
                candidate.extend_from_slice(mv);
                let digest = blake3_hash(&candidate);
                fitness_from_hash_biguint(&digest, &target)
            })
            .collect();

        // 解が存在するか検査
        for (i, f) in fitness.iter().enumerate() {
            if *f == 1.0 {
                let elapsed = start.elapsed();
                println!(
                    "FOUND solution generation={} idx={} mv={} time={:?}",
                    gen,
                    i,
                    hex::encode(&population_vec[i]),
                    elapsed
                );
                return;
            }
        }

        // 選択（トーナメント）、交叉（1 点）、突然変異
        // 新しい個体群の構築
        let mut new_pop = Vec::with_capacity(population);
        for _ in 0..population {
            // トーナメント選択
            let idx1 = rng.gen_range(0..population);
            let idx2 = rng.gen_range(0..population);
            let parent = if fitness[idx1] > fitness[idx2] {
                &population_vec[idx1]
            } else {
                &population_vec[idx2]
            };
            let idx3 = rng.gen_range(0..population);
            let idx4 = rng.gen_range(0..population);
            let parent2 = if fitness[idx3] > fitness[idx4] {
                &population_vec[idx3]
            } else {
                &population_vec[idx4]
            };

            // 交叉
            let mut child = vec![0u8; mv_len];
            let cross_point = rng.gen_range(0..mv_len);
            for i in 0..mv_len {
                child[i] = if i < cross_point { parent[i] } else { parent2[i] };
            }
            // 突然変異: ランダムなバイトを反転/置換
            if rng.gen_bool(0.02) {
                let mpos = rng.gen_range(0..mv_len);
                child[mpos] = rng.gen();
            }
            new_pop.push(child);
        }

        population_vec = new_pop;

        if gen % 10 == 0 {
            let best_f = fitness.iter().cloned().fold(f64::NAN, f64::max);
            let elapsed = start.elapsed();
            println!("gen={} best_f={} time={:?}", gen, best_f, elapsed);
        }
    }
    println!(
        "GA finished without finding solution after {} generations",
        generations
    );
}

fn main() {
    let args = Args::parse();
    if args.threads > 0 {
        rayon::ThreadPoolBuilder::new()
            .num_threads(args.threads)
            .build_global()
            .unwrap();
    }

    // 入力の解析
    let header_bytes_all = hex_to_bytes(&args.header_hex);
    // header_hex は mutationVector 直前までのプレフィックス（= mutationVector より前の全シリアライズ項目）を想定
    // 簡略化のため、ユーザーがこのヘッダプレフィックス（mutationVector 本体は含まない）を与える前提
    let header_prefix = Arc::new(header_bytes_all);

    let bits_u32 = parse_bits_hex(&args.bits_hex);
    let target = compact_bits_to_target(bits_u32);

    if args.brute {
        run_bruteforce(header_prefix, &target, args.mv_len);
    } else {
        run_ga(
            header_prefix,
            &target,
            args.mv_len,
            args.population,
            args.generations,
        );
    }

    println!("done");
}

// メモ: GPU 連携
// - BLAKE3 は CPU でも高速で SIMD 実装があります。GPU 加速の方針:
//   * OpenCL: blake3 の OpenCL 版を用意し、`ocl` クレートで大量の候補をカーネルへ投入
//   * CUDA: Rust の CUDA バインディング、または CUDA カーネルを作成して FFI 経由で呼び出し
// - 代替案として、GA ロジックは Rust 側に置き、GPU カーネルには blake3(データ)->digest のみを一括委譲
// - 本番ではベンチマーク推奨: blake3 + rayon + CPU SIMD だけでも高い H/s が見込める。GPU は最適化とメモリアクセスが鍵

// セキュリティと性能:
// - mutationVector のサイズに上限を設ける（極端に大きいヘッダによる DoS 回避）
// - ホットパスでは事前確保したバッファを再利用して割当てコストを削減
// - ハッシュ比較は BigUint ではなく u256 風の固定長配列でバイト比較すると高性能

// 実行例:
// cargo run --release -- --header-hex <prefix-hex> --bits-hex 1f00ffff --mv-len 16 --population 1024 --generations 2000
