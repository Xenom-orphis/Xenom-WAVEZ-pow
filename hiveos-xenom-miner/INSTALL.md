# Quick Installation Guide for HiveOS

## Step 1: Package the Miner

On your development machine (where you have the code):

```bash
cd /Users/hainz/code/Waves_Pow
./hiveos-xenom-miner/PACKAGE.sh
```

This will create `xenom-miner-1.0.0.tar.gz` in the current directory.

## Step 2: Upload to HiveOS

Choose one of these methods:

### Option A: Upload via HiveOS Web Interface
1. Go to HiveOS web dashboard
2. Navigate to your rig
3. Use the file upload feature to upload `xenom-miner-1.0.0.tar.gz`

### Option B: Upload via SCP
```bash
scp xenom-miner-1.0.0.tar.gz user@your-rig-ip:/tmp/
```

### Option C: Host on Web Server
```bash
# Upload to your web server, then on HiveOS rig:
wget http://your-server.com/xenom-miner-1.0.0.tar.gz -O /tmp/xenom-miner-1.0.0.tar.gz
```

## Step 3: Install on HiveOS Rig

SSH into your HiveOS rig and run:

```bash
# Extract the package
cd /tmp
tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/

# Set permissions
chmod +x /hive/miners/custom/xenom-miner/*.sh

# Verify installation
ls -la /hive/miners/custom/xenom-miner/
```

## Step 4: Configure Flight Sheet

1. **Go to HiveOS Dashboard** → Flight Sheets
2. **Create New Flight Sheet** or edit existing
3. **Configure:**
   - **Coin:** Custom
   - **Wallet:** Create a wallet with your Xenom address
   - **Pool:** Create a pool with your node URL (e.g., `http://eu.losmuchachos.digital:36669`)
   - **Miner:** Select "Custom"
   - **Setup Miner Config:**
     ```
     Miner name: xenom-miner
     Installation URL: (leave empty - already installed)
     Hash algorithm: xenom-pow
     Wallet and worker template: %WAL%
     Pool URL: %URL%
     Extra config arguments: (optional)
     ```

4. **Apply Flight Sheet** to your rig

## Step 5: Verify It's Working

Check miner status:
```bash
# View miner logs
tail -f /var/log/miner/custom/xenom-miner/xenom.log

# Check if miner is running
ps aux | grep xenom

# Check HiveOS miner stats
miner log
```

## Configuration Examples

### Basic Configuration (HiveOS Flight Sheet)
- **Pool URL:** `http://eu.losmuchachos.digital:36669`
- **Wallet:** `your_xenom_wallet_address`

### Advanced Configuration (Extra Config)
```json
{
  "miner_address": "your_custom_address",
  "threads": 8,
  "mv_len": 16
}
```

## Troubleshooting

### Miner doesn't start
```bash
# Check if Rust is installed
cargo --version

# If not, install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Try building manually
cd /hive/miners/custom/xenom-miner/xenom-miner-rust
cargo build --release
```

### Can't connect to node
```bash
# Test node connectivity
curl http://eu.losmuchachos.digital:36669/mining/template

# Check if you can reach the node
ping eu.losmuchachos.digital
```

### View detailed logs
```bash
# Full log
cat /var/log/miner/custom/xenom-miner/xenom.log

# Last 100 lines
tail -100 /var/log/miner/custom/xenom-miner/xenom.log

# Follow live
tail -f /var/log/miner/custom/xenom-miner/xenom.log
```

## Updating the Miner

To update:
1. Create new package with updated version
2. Stop miner in HiveOS
3. Extract new package (will overwrite old files)
4. Restart miner

```bash
# Stop miner
miner stop

# Extract new version
tar -xzf xenom-miner-1.0.1.tar.gz -C /hive/miners/custom/

# Start miner
miner start
```

## Support

- Check logs first: `/var/log/miner/custom/xenom-miner/xenom.log`
- Verify node is accessible
- Ensure wallet address is valid
- Check HiveOS system logs: `journalctl -u hive`
