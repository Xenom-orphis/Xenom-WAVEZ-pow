use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    #[cfg(feature = "cuda")]
    {
        println!("cargo:rerun-if-changed=src/blake3.cu");

        let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
        let cu_file = "src/blake3.cu";
        let ptx_file = out_dir.join("blake3.ptx");

        // Try to find nvcc
        let nvcc = which::which("nvcc").unwrap_or_else(|_| {
            panic!("nvcc not found. Please install CUDA Toolkit and ensure nvcc is in PATH");
        });

        println!("cargo:warning=Compiling CUDA kernel with nvcc...");

        // Compile CUDA to PTX
        let output = Command::new(nvcc)
            .args(&[
                "--ptx",
                cu_file,
                "-o",
                ptx_file.to_str().unwrap(),
                "-arch=sm_60", // Compute capability 6.0+ (Pascal and newer)
                "--use_fast_math",
                "-O3",
            ])
            .output()
            .expect("Failed to execute nvcc");

        if !output.status.success() {
            panic!(
                "nvcc failed:\nstdout: {}\nstderr: {}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        // Export PTX path so the binary can load it at runtime
        println!("cargo:rustc-env=CUDA_BLAKE3_PTX={}", ptx_file.display());
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
