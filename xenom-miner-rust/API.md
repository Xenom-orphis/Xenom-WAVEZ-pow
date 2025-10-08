# Xenom Miner API Documentation

The Xenom miner exposes a REST API for monitoring mining statistics in real-time.

## Configuration

The API server is automatically started when running in `--mine-loop` mode with GPU enabled.

### Command Line Option

```bash
--api-port <PORT>    # API server port (default: 3333)
```

### Example

```bash
./xenom-miner-rust --mine-loop --node-url http://localhost:36669 --gpu --gpu-brute --api-port 3333
```

## Endpoints

### GET /stats

Returns current mining statistics in JSON format.

**Response:**

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

**Fields:**

- `uptime_secs`: Miner uptime in seconds since start
- `current_height`: Current block height being mined
- `total_hashes`: Total number of hashes computed
- `hashrate_mhs`: Total hashrate in MH/s (megahashes per second)
- `accepted_shares`: Number of accepted solutions
- `rejected_shares`: Number of rejected solutions
- `gpu_count`: Number of GPUs being used
- `per_gpu_hashrate_mhs`: Array of hashrates for each GPU in MH/s
- `mining`: Boolean indicating if currently mining
- `last_solution_time`: Timestamp of last solution found (seconds since start), or null
- `version`: Miner version

### GET /health

Health check endpoint.

**Response:**

```json
{
  "status": "ok"
}
```

## Usage Examples

### cURL

```bash
# Get mining stats
curl http://localhost:3333/stats

# Health check
curl http://localhost:3333/health
```

### HiveOS Integration

The `h-stats.sh` script automatically reads from the API endpoint to provide real-time statistics to HiveOS:

```bash
# The script will try to read from the API first
# Falls back to log parsing if API is unavailable
./h-stats.sh
```

### Python

```python
import requests

response = requests.get('http://localhost:3333/stats')
stats = response.json()

print(f"Hashrate: {stats['hashrate_mhs']} MH/s")
print(f"Accepted: {stats['accepted_shares']}")
print(f"Rejected: {stats['rejected_shares']}")
```

### JavaScript

```javascript
fetch('http://localhost:3333/stats')
  .then(response => response.json())
  .then(stats => {
    console.log(`Hashrate: ${stats.hashrate_mhs} MH/s`);
    console.log(`Accepted: ${stats.accepted_shares}`);
    console.log(`Rejected: ${stats.rejected_shares}`);
  });
```

## CORS

The API includes CORS headers (`Access-Control-Allow-Origin: *`) to allow access from web applications.

## Notes

- The API server runs on a separate thread and does not impact mining performance
- Statistics are updated in real-time as mining progresses
- The API is only available when running in `--mine-loop` mode with GPU enabled
- For security, the API binds to `0.0.0.0` but should only be accessed from trusted networks
