# Xenom PoW Miner - HiveOS Custom Miner

This is a HiveOS custom miner package for the Xenom Proof-of-Work blockchain.

## Features

- ✅ Full HiveOS integration with stats reporting
- ✅ Pre-compiled binary (no build required on HiveOS)
- ✅ **GPU mining support** (NVIDIA CUDA) with auto-detection
- ✅ Multi-GPU support
- ✅ CPU mining fallback
- ✅ Configurable mining address
- ✅ Block submission tracking (accepted/rejected)
- ✅ Multi-threaded CPU mining support

## Installation

### Method 1: From Archive (Recommended for HiveOS)

1. **Package the miner:**
   ```bash
   # On your development machine
   cd /path/to/Waves_Pow
   
   # Run the packaging script (builds binary and creates archive)
   ./hiveos-xenom-miner/PACKAGE.sh
   ```

2. **Upload to your HiveOS rig:**
   - Upload `xenom-miner-1.0.0.tar.gz` to your rig (via web interface or SCP)
   - Or host it on a web server and download directly on the rig

3. **Install on HiveOS:**
   ```bash
   # SSH into your HiveOS rig
   cd /tmp
   
   # If uploaded locally:
   tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/
   
   # Or download from URL:
   wget http://your-server.com/xenom-miner-1.0.0.tar.gz
   tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/
   
   # Set execute permissions
   chmod +x /hive/miners/custom/xenom-miner/*.sh
   ```

### Method 2: Manual Installation

1. **Clone directly on HiveOS rig:**
   ```bash
   cd /hive/miners/custom/
   git clone <your-repo-url> xenom-miner
   cd xenom-miner
   chmod +x *.sh
   ```

## Configuration in HiveOS

### Flight Sheet Setup

1. Go to your HiveOS dashboard
2. Create or edit a Flight Sheet
3. Select **Custom Miner** as the miner
4. Configure as follows:

   - **Miner name:** `xenom-miner`
   - **Installation URL:** Leave empty (already installed)
   - **Hash algorithm:** `xenom-pow`
   - **Wallet and worker template:** Your Xenom wallet address
   - **Pool URL:** Your Xenom node URL (e.g., `http://eu.losmuchachos.digital:36669`)
   - **Extra config arguments:** (Optional JSON)
     ```json
     {
       "miner_address": "your_xenom_address_here"
     }
     ```

### Configuration Options

The miner accepts the following configuration through HiveOS:

- **Pool URL** (`CUSTOM_URL`): The Xenom node URL to connect to
- **Wallet Template** (`CUSTOM_TEMPLATE`): Your mining reward address
- **User Config** (`CUSTOM_USER_CONFIG`): JSON with additional options:
  ```json
  {
    "miner_address": "your_address",
    "threads": 0,
    "mv_len": 16,
    "use_gpu": true,
    "gpu_id": 0,
    "multi_gpu": false,
    "gpu_batches": 40000
  }
  ```

### Configuration Options Explained

**CPU Mining:**
- `threads`: Number of CPU threads (0 = auto-detect all cores)
- `mv_len`: Mutation vector length (default: 16)

**GPU Mining:**
- `use_gpu`: Enable GPU mining (default: auto-detected if NVIDIA GPU present)
- `gpu_id`: Which GPU to use (0-based index, default: 0)
- `multi_gpu`: Enable all GPUs (default: false, auto-enabled if multiple GPUs detected)
- `gpu_batches`: Number of GPU batches per iteration (default: 40000)

### Default Values

- **Node URL:** `http://eu.losmuchachos.digital:36669`
- **Threads:** `0` (auto-detect CPU cores)
- **MV Length:** `16`
- **GPU:** Auto-detected (enabled if NVIDIA GPU found)
- **Miner Address:** If not specified, rewards go to the node's wallet

## File Structure

```
xenom-miner/
├── h-manifest.conf       # HiveOS manifest configuration
├── h-config.sh          # Config generator script
├── h-run.sh             # Miner startup script
├── h-stats.sh           # Stats reporting script
├── mine-loop.sh         # Main mining loop
├── bin/
│   └── xenom-miner-rust # Pre-compiled miner binary
└── README.md            # This file
```

## Monitoring

The miner reports the following statistics to HiveOS:

- **Hashrate:** Approximate hash rate
- **Accepted/Rejected:** Number of blocks accepted/rejected by the node
- **Uptime:** Miner uptime in seconds
- **Current Height:** Current block being mined

## Logs

Logs are stored at:
```
/var/log/miner/custom/xenom-miner/xenom.log
```

View logs:
```bash
tail -f /var/log/miner/custom/xenom-miner/xenom.log
```

## Troubleshooting

### Miner won't start

1. Check if binary exists:
   ```bash
   ls -la /hive/miners/custom/xenom-miner/bin/xenom-miner-rust
   ```

2. Check logs for errors:
   ```bash
   tail -100 /var/log/miner/custom/xenom-miner/xenom.log
   ```

3. Verify permissions:
   ```bash
   chmod +x /hive/miners/custom/xenom-miner/bin/xenom-miner-rust
   chmod +x /hive/miners/custom/xenom-miner/*.sh
   ```

### No blocks found

- Check if the node URL is correct and accessible
- Verify the node is running and synced
- Check network connectivity: `curl http://your-node-url/mining/template`

### Binary not found

- Ensure the package was extracted correctly
- Re-download and extract the package
- Check that `/hive/miners/custom/xenom-miner/bin/` directory exists

## Support

For issues and questions:
- Check the logs first
- Verify your node is accessible
- Ensure your wallet address is valid

## License

Same as the Xenom project license.
