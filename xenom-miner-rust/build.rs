use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    #[cfg(feature = "cuda")]
    {
        println!("cargo:rerun-if-changed=src/blake3_simple.cu");

        let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
        let cu_file = "src/blake3.cu";
        let ptx_file = out_dir.join("blake3.ptx");

        // Try to find nvcc
        let nvcc = which::which("nvcc").unwrap_or_else(|_| {
            panic!("nvcc not found. Please install CUDA Toolkit and ensure nvcc is in PATH");
        });

        println!("cargo:warning=Compiling CUDA kernel with nvcc at {:?}...", nvcc);

        // Compile CUDA to PTX
        // Determine compute capability (use sm_75 as modern default for Turing/Volta+)
        let arch = std::env::var("CUDA_ARCH").unwrap_or_else(|_| "sm_75".to_string());
        println!("cargo:warning=Using CUDA compute capability: {}", arch);
        
        // Use simplified Blake3 implementation
        let output = std::process::Command::new("nvcc")
            .args(&[
                "--ptx",
                "src/blake3_simple.cu",
                "-o",
                ptx_file.to_str().unwrap(),
                &format!("-arch={}", arch),
                "--use_fast_math",
                "-O3",
            ])
            .output()
            .expect("Failed to run nvcc. Ensure CUDA Toolkit is installed and nvcc is in PATH.");

        if !output.status.success() {
            panic!(
                "nvcc failed:\nstdout: {}\nstderr: {}\n\nTry setting CUDA_ARCH environment variable:\n  RTX 50 series: CUDA_ARCH=sm_90\n  RTX 40 series: CUDA_ARCH=sm_89\n  RTX 30 series: CUDA_ARCH=sm_86\n  RTX 20 series: CUDA_ARCH=sm_75",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }
        println!("cargo:rustc-env=CUDA_BLAKE3_PTX={}", ptx_file.display());
        
        // Also copy PTX to project root for easier deployment
        let root_ptx = PathBuf::from("blake3.ptx");
        if let Err(e) = std::fs::copy(&ptx_file, &root_ptx) {
            println!("cargo:warning=Failed to copy PTX to project root: {}", e);
        } else {
            println!("cargo:warning=PTX also copied to {}", root_ptx.display());
        }
        
        println!(
            "cargo:warning=CUDA kernel compiled successfully to {}",
            ptx_file.display()
        );
    }

    #[cfg(not(feature = "cuda"))]
    {
        println!("cargo:warning=Building without CUDA support. Use --features cuda to enable GPU acceleration.");
    }
}
