use serde::{Deserialize, Serialize};
use std::error::Error;

#[derive(Debug, Deserialize)]
pub struct MiningTemplate {
    pub height: u64,
    pub header_prefix_hex: String,
    pub difficulty_bits: String,
    pub target_hex: String,
    pub timestamp: u64,
    pub miner_address: String,
}

#[derive(Debug, Serialize)]
pub struct MiningSubmission {
    pub height: u64,
    pub mutation_vector_hex: String,
    pub timestamp: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub miner_address: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SubmissionResponse {
    pub success: bool,
    pub message: String,
    pub hash: Option<String>,
}

pub struct NodeClient {
    base_url: String,
    client: reqwest::blocking::Client,
    miner_address: Option<String>,
}

impl NodeClient {
    pub fn new(base_url: String) -> Self {
        Self {
            base_url,
            client: reqwest::blocking::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("Failed to create HTTP client"),
            miner_address: None,
        }
    }

    pub fn with_miner_address(mut self, address: String) -> Self {
        self.miner_address = Some(address);
        self
    }

    pub fn get_template(&self) -> Result<MiningTemplate, Box<dyn Error>> {
        let mut url = format!("{}/mining/template", self.base_url);
        
        // Add miner address as query parameter if provided
        if let Some(addr) = &self.miner_address {
            url = format!("{}?address={}", url, addr);
        }
        
        let response = self.client.get(&url).send()?;
        
        if !response.status().is_success() {
            return Err(format!("HTTP error: {}", response.status()).into());
        }
        
        let template: MiningTemplate = response.json()?;
        Ok(template)
    }

    pub fn submit_solution(
        &self,
        height: u64,
        mutation_vector_hex: &str,
        timestamp: u64,
    ) -> Result<SubmissionResponse, Box<dyn Error>> {
        let url = format!("{}/mining/submit", self.base_url);
        
        let submission = MiningSubmission {
            height,
            mutation_vector_hex: mutation_vector_hex.to_string(),
            timestamp,
            miner_address: self.miner_address.clone(),
        };
        
        let response = self.client
            .post(&url)
            .json(&submission)
            .send()?;
        
        if !response.status().is_success() {
            return Err(format!("HTTP error: {}", response.status()).into());
        }
        
        let result: SubmissionResponse = response.json()?;
        Ok(result)
    }
}
