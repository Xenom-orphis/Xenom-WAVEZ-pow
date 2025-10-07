# HiveOS Xenom Miner - Quick Start

## 🚀 One-Command Package & Deploy

### 1. Package the Miner
```bash
cd /Users/hainz/code/Waves_Pow
./hiveos-xenom-miner/PACKAGE.sh
```
This creates `xenom-miner-1.0.0.tar.gz`

### 2. Deploy to HiveOS
```bash
# Upload to your rig (replace with your rig IP)
scp xenom-miner-1.0.0.tar.gz user@YOUR_RIG_IP:/tmp/

# SSH into rig and install
ssh user@YOUR_RIG_IP
cd /tmp
tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/
chmod +x /hive/miners/custom/xenom-miner/*.sh
ls -la /hive/miners/custom/xenom-miner/  # Verify installation
```

### 3. Configure in HiveOS Dashboard

**Create Flight Sheet:**
- **Miner:** Custom
- **Miner Name:** `xenom-miner`
- **Pool URL:** `http://eu.losmuchachos.digital:36669`
- **Wallet:** Your Xenom address
- **Extra Config:** (optional)
  ```json
  {"miner_address": "your_address"}
  ```

### 4. Start Mining
Apply the flight sheet to your rig and watch it mine!

## 📊 Monitor

```bash
# View logs
tail -f /var/log/miner/custom/xenom-miner/xenom.log

# Check stats
miner log
```

## 📁 Package Contents

```
hiveos-xenom-miner/
├── h-manifest.conf    # HiveOS configuration
├── h-config.sh        # Config generator
├── h-run.sh           # Miner launcher
├── h-stats.sh         # Stats reporter
├── mine-loop.sh       # Mining loop
├── PACKAGE.sh         # Packaging script
├── README.md          # Full documentation
├── INSTALL.md         # Detailed installation
└── QUICKSTART.md      # This file
```

## ⚙️ How It Works

1. **h-config.sh** - Generates config from HiveOS flight sheet settings
2. **h-run.sh** - Builds the Rust miner (first run) and starts mining
3. **mine-loop.sh** - Fetches templates, mines blocks, submits solutions
4. **h-stats.sh** - Reports mining stats to HiveOS dashboard

## 🔧 Configuration Options

Set in HiveOS Flight Sheet "Extra Config":

```json
{
  "miner_address": "your_xenom_wallet_address",
  "threads": 0,
  "mv_len": 16
}
```

- **miner_address**: Where mining rewards go (default: node wallet)
- **threads**: CPU threads to use (0 = auto-detect all cores)
- **mv_len**: Mutation vector length (default: 16)

## 📈 Stats Reported to HiveOS

- ✅ Hashrate (approximate)
- ✅ Accepted/Rejected blocks
- ✅ Uptime
- ✅ Current mining height
- ✅ Algorithm: xenom-pow

## 🐛 Troubleshooting

**Miner won't build?**
```bash
# Install Rust on HiveOS rig
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

**Can't connect to node?**
```bash
# Test node connectivity
curl http://eu.losmuchachos.digital:36669/mining/template
```

**Check logs:**
```bash
tail -100 /var/log/miner/custom/xenom-miner/xenom.log
```

## 📚 More Info

- **Full README:** See `README.md` for complete documentation
- **Installation Guide:** See `INSTALL.md` for step-by-step instructions
- **HiveOS Custom Miners:** https://github.com/minershive/hiveos-linux/blob/master/hive/miners/custom/README.md

## 🎯 Quick Test

After installation, test manually:
```bash
cd /hive/miners/custom/xenom-miner
export NODE_URL="http://eu.losmuchachos.digital:36669"
export MINER_ADDRESS="your_address"
./h-run.sh
```

Press Ctrl+C to stop, then use HiveOS dashboard to manage it normally.
