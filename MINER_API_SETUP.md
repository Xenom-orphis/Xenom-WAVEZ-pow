# Miner API Setup Guide

## Overview

The Xenom miner now includes a built-in REST API that exposes real-time mining statistics. The HiveOS integration (`h-stats.sh`) automatically reads from this API instead of parsing logs, providing accurate and up-to-date statistics.

## Features

✅ **Real-time statistics** - No more log parsing delays  
✅ **Accurate hashrate** - Per-GPU and total hashrate tracking  
✅ **Share counting** - Accepted and rejected shares  
✅ **Automatic fallback** - Falls back to log parsing if API unavailable  
✅ **Zero configuration** - Works out of the box with default settings  

## Building the Miner

### With CUDA Support (Required for API)

```bash
cd xenom-miner-rust
cargo build --release --features cuda
```

The binary will be at: `target/release/xenom-miner-rust`

### Without CUDA (API not available)

```bash
cd xenom-miner-rust
cargo build --release
```

Note: The API is only available when running with GPU/CUDA support.

## Running the Miner

### Basic Usage

```bash
./xenom-miner-rust \
  --mine-loop \
  --node-url http://localhost:36669 \
  --gpu \
  --gpu-brute \
  --api-port 3333
```

### With Custom Configuration

```bash
./xenom-miner-rust \
  --mine-loop \
  --node-url http://your-node:36669 \
  --miner-address 3Mxxx... \
  --gpu \
  --gpu-brute \
  --batches 40000 \
  --api-port 3333
```

## API Endpoints

### GET /stats

Returns mining statistics in JSON format:

```json
{
  "uptime_secs": 3600,
  "current_height": 12345,
  "total_hashes": 1000000000,
  "hashrate_mhs": 125.5,
  "accepted_shares": 5,
  "rejected_shares": 0,
  "gpu_count": 2,
  "per_gpu_hashrate_mhs": [62.5, 63.0],
  "mining": true,
  "last_solution_time": 3500,
  "version": "0.1.0"
}
```

### GET /health

Health check endpoint:

```json
{
  "status": "ok"
}
```

## Testing the API

### Using cURL

```bash
# Get stats
curl http://localhost:3333/stats | jq

# Health check
curl http://localhost:3333/health
```

### Using Browser

Simply open: http://localhost:3333/stats

## HiveOS Integration

### Configuration

The HiveOS integration automatically uses the API. You can configure the API port in the miner settings:

**In HiveOS Flight Sheet:**
- Add to "Extra config arguments" (JSON format):
  ```json
  {
    "api_port": 3333
  }
  ```

### How It Works

1. `h-stats.sh` attempts to fetch stats from `http://localhost:3333/stats`
2. If successful, it uses the real-time data from the API
3. If API is unavailable, it falls back to parsing logs (legacy method)
4. GPU temperature and fan data still comes from HiveOS GPU stats

### Files Modified

- **h-stats.sh** - Reads from API first, falls back to logs
- **h-config.sh** - Added API_PORT configuration
- **h-run.sh** - Exports API_PORT environment variable
- **mine-loop.sh** - Passes --api-port to miner

## Troubleshooting

### API Not Responding

1. **Check if miner is running:**
   ```bash
   ps aux | grep xenom-miner
   ```

2. **Check if API port is listening:**
   ```bash
   netstat -tulpn | grep 3333
   ```

3. **Test API directly:**
   ```bash
   curl -v http://localhost:3333/health
   ```

### Port Already in Use

If port 3333 is already in use, change it:

```bash
./xenom-miner-rust --mine-loop --gpu --api-port 3334
```

And update in HiveOS config:
```json
{
  "api_port": 3334
}
```

### Stats Not Updating in HiveOS

1. Check miner logs for errors
2. Verify API is responding: `curl http://localhost:3333/stats`
3. Check h-stats.sh is using the correct port
4. Restart the miner

## Performance Impact

The API server runs on a separate thread and has **minimal performance impact**:
- ~0.1% CPU usage for API server
- No impact on mining performance
- Responses are cached and updated in real-time

## Security Notes

- The API binds to `0.0.0.0` (all interfaces) by default
- **Only expose to trusted networks**
- No authentication is implemented (stats are read-only)
- Consider using a firewall to restrict access if needed

## Advanced Usage

### Monitoring Multiple Miners

You can monitor multiple miners by using different ports:

```bash
# Miner 1
./xenom-miner-rust --mine-loop --gpu --api-port 3333

# Miner 2
./xenom-miner-rust --mine-loop --gpu --api-port 3334
```

### Creating a Dashboard

The API can be used to create monitoring dashboards:

```python
import requests
import time

while True:
    response = requests.get('http://localhost:3333/stats')
    stats = response.json()
    
    print(f"Hashrate: {stats['hashrate_mhs']:.2f} MH/s")
    print(f"Accepted: {stats['accepted_shares']}")
    print(f"Rejected: {stats['rejected_shares']}")
    print(f"Uptime: {stats['uptime_secs']}s")
    print("-" * 40)
    
    time.sleep(10)
```

## See Also

- [API.md](xenom-miner-rust/API.md) - Complete API documentation
- [README.md](README.md) - Main project documentation
