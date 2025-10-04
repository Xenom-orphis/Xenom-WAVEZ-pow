use serde::{Deserialize, Serialize};
use std::error::Error;

#[derive(Debug, Deserialize)]
pub struct MiningTemplate {
    pub height: u64,
    pub header_prefix_hex: String,
    pub difficulty_bits: String,
    pub target_hex: String,
    pub timestamp: u64,
}

#[derive(Debug, Serialize)]
pub struct MiningSubmission {
    pub height: u64,
    pub mutation_vector_hex: String,
    pub timestamp: u64,
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
}

impl NodeClient {
    pub fn new(base_url: String) -> Self {
        Self {
            base_url,
            client: reqwest::blocking::Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .expect("Failed to create HTTP client"),
        }
    }

    pub fn get_template(&self) -> Result<MiningTemplate, Box<dyn Error>> {
        let url = format!("{}/mining/template", self.base_url);
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
