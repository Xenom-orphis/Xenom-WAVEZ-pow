use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MinerStats {
    pub uptime_secs: u64,
    pub current_height: u64,
    pub total_hashes: u64,
    pub hashrate_mhs: f64,
    pub accepted_shares: u64,
    pub rejected_shares: u64,
    pub gpu_count: usize,
    pub per_gpu_hashrate_mhs: Vec<f64>,
    pub mining: bool,
    pub last_solution_time: Option<u64>,
    pub version: String,
}

impl Default for MinerStats {
    fn default() -> Self {
        Self {
            uptime_secs: 0,
            current_height: 0,
            total_hashes: 0,
            hashrate_mhs: 0.0,
            accepted_shares: 0,
            rejected_shares: 0,
            gpu_count: 0,
            per_gpu_hashrate_mhs: Vec::new(),
            mining: false,
            last_solution_time: None,
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }
}

pub struct StatsTracker {
    stats: Arc<RwLock<MinerStats>>,
    start_time: Instant,
}

impl StatsTracker {
    pub fn new(gpu_count: usize) -> Self {
        let mut stats = MinerStats::default();
        stats.gpu_count = gpu_count;
        stats.per_gpu_hashrate_mhs = vec![0.0; gpu_count];
        
        Self {
            stats: Arc::new(RwLock::new(stats)),
            start_time: Instant::now(),
        }
    }

    pub fn get_stats(&self) -> Arc<RwLock<MinerStats>> {
        Arc::clone(&self.stats)
    }

    pub fn update_height(&self, height: u64) {
        let mut stats = self.stats.write();
        stats.current_height = height;
    }

    pub fn update_hashrate(&self, total_hashes: u64, elapsed: Duration, gpu_id: Option<usize>) {
        let mut stats = self.stats.write();
        stats.total_hashes += total_hashes;
        stats.uptime_secs = self.start_time.elapsed().as_secs();
        
        let hashrate_mhs = total_hashes as f64 / elapsed.as_secs_f64() / 1_000_000.0;
        
        if let Some(id) = gpu_id {
            if id < stats.per_gpu_hashrate_mhs.len() {
                stats.per_gpu_hashrate_mhs[id] = hashrate_mhs;
            }
        }
        
        // Calculate total hashrate
        stats.hashrate_mhs = stats.per_gpu_hashrate_mhs.iter().sum();
    }

    pub fn increment_accepted(&self) {
        let mut stats = self.stats.write();
        stats.accepted_shares += 1;
        stats.last_solution_time = Some(self.start_time.elapsed().as_secs());
    }

    pub fn increment_rejected(&self) {
        let mut stats = self.stats.write();
        stats.rejected_shares += 1;
    }

    pub fn set_mining(&self, mining: bool) {
        let mut stats = self.stats.write();
        stats.mining = mining;
    }
}

pub fn start_api_server(stats: Arc<RwLock<MinerStats>>, port: u16) {
    std::thread::spawn(move || {
        let server = match tiny_http::Server::http(format!("0.0.0.0:{}", port)) {
            Ok(s) => {
                println!("📊 Stats API server started on http://0.0.0.0:{}", port);
                s
            }
            Err(e) => {
                eprintln!("❌ Failed to start stats API server: {}", e);
                return;
            }
        };

        for request in server.incoming_requests() {
            let path = request.url();
            
            match path {
                "/stats" | "/api/stats" => {
                    let stats_data = stats.read().clone();
                    let json = serde_json::to_string_pretty(&stats_data).unwrap_or_else(|_| "{}".to_string());
                    
                    let response = tiny_http::Response::from_string(json)
                        .with_header(
                            tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
                        )
                        .with_header(
                            tiny_http::Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..]).unwrap()
                        );
                    
                    let _ = request.respond(response);
                }
                "/health" => {
                    let response = tiny_http::Response::from_string(r#"{"status":"ok"}"#)
                        .with_header(
                            tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
                        );
                    
                    let _ = request.respond(response);
                }
                _ => {
                    let response = tiny_http::Response::from_string(r#"{"error":"not found"}"#)
                        .with_status_code(404)
                        .with_header(
                            tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).unwrap()
                        );
                    
                    let _ = request.respond(response);
                }
            }
        }
    });
}
