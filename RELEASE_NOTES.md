# Xenom HiveOS Miner v1.0.0

## 🎉 First Release - HiveOS Custom Miner Package

This release introduces a complete HiveOS custom miner integration for Xenom PoW blockchain mining.

## 📦 Download

**Package:** [xenom-miner-1.0.0.tar.gz](https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/releases/download/v1.0.0/xenom-miner-1.0.0.tar.gz)

## ✨ Features

- ✅ **Full HiveOS Integration** - Seamless integration with HiveOS dashboard and monitoring
- ✅ **Automatic Building** - Builds Rust miner binary automatically on first run
- ✅ **Real-time Stats** - Reports hashrate, accepted/rejected blocks, and uptime to HiveOS
- ✅ **Configurable** - Easy configuration via HiveOS Flight Sheets
- ✅ **Multi-threaded** - Supports configurable CPU threading (auto-detect by default)
- ✅ **Production Ready** - Battle-tested mining loop with error handling

## 🚀 Quick Installation

### 1. Download and Install

```bash
# On your HiveOS rig
cd /tmp
wget https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/releases/download/v1.0.0/xenom-miner-1.0.0.tar.gz
tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/
chmod +x /hive/miners/custom/xenom-miner/*.sh

# Verify installation
ls -la /hive/miners/custom/xenom-miner/
```

### 2. Configure Flight Sheet

In HiveOS Dashboard:
- **Miner:** Custom
- **Miner Name:** `xenom-miner`
- **Pool URL:** `http://eu.losmuchachos.digital:36669` (or your node URL)
- **Wallet:** Your Xenom wallet address

### 3. Start Mining!

Apply the flight sheet to your rig and start earning Xenom!

## ⚙️ Configuration

### Basic Setup
Set in HiveOS Flight Sheet:
- **Pool URL:** Your Xenom node endpoint
- **Wallet:** Your mining reward address

### Advanced Configuration
Add to "Extra Config Arguments" (JSON format):
```json
{
  "miner_address": "your_xenom_wallet_address",
  "threads": 0,
  "mv_len": 16
}
```

**Options:**
- `miner_address` - Wallet address for mining rewards (default: node wallet)
- `threads` - Number of CPU threads (0 = auto-detect all cores)
- `mv_len` - Mutation vector length (default: 16)

## 📊 Monitoring

The miner reports to HiveOS:
- **Hashrate** - Approximate hash rate
- **Accepted Shares** - Successfully mined blocks
- **Rejected Shares** - Rejected block submissions
- **Uptime** - Miner runtime
- **Current Height** - Block height being mined

View logs:
```bash
tail -f /var/log/miner/custom/xenom-miner/xenom.log
```

## 📋 Requirements

- **HiveOS** - Latest version recommended
- **Rust & Cargo** - Auto-installed if needed
- **jq** - JSON processor (usually pre-installed on HiveOS)
- **curl** - HTTP client (pre-installed on HiveOS)
- **Internet Connection** - To communicate with Xenom node

### Installing Rust (if needed)
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

## 📁 Package Contents

```
xenom-miner/
├── h-manifest.conf    # HiveOS miner manifest
├── h-config.sh        # Configuration generator
├── h-run.sh           # Miner startup script
├── h-stats.sh         # Stats reporter for HiveOS
├── mine-loop.sh       # Main mining loop
├── xenom-miner-rust/  # Rust miner source code
├── README.md          # Complete documentation
├── INSTALL.md         # Detailed installation guide
└── QUICKSTART.md      # Quick start guide
```

## 🔧 Troubleshooting

### Miner won't start
```bash
# Check logs
tail -100 /var/log/miner/custom/xenom-miner/xenom.log

# Verify Rust installation
cargo --version

# Check miner process
ps aux | grep xenom
```

### Can't connect to node
```bash
# Test node connectivity
curl http://your-node-url:36669/mining/template

# Check network
ping your-node-url
```

### Build failures
```bash
# Manual build
cd /hive/miners/custom/xenom-miner/xenom-miner-rust
cargo build --release
```

## 📖 Documentation

- **README.md** - Complete reference documentation
- **INSTALL.md** - Step-by-step installation guide
- **QUICKSTART.md** - Fast deployment guide
- **HiveOS Custom Miners Guide** - https://github.com/minershive/hiveos-linux/blob/master/hive/miners/custom/README.md

## 🐛 Known Issues

None at this time. Please report any issues on GitHub.

## 🔄 Updating

To update to a newer version:
```bash
miner stop
cd /tmp
wget https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/releases/download/vX.X.X/xenom-miner-X.X.X.tar.gz
tar -xzf xenom-miner-X.X.X.tar.gz -C /hive/miners/custom/
chmod +x /hive/miners/custom/xenom-miner/*.sh
miner start
```

## 💬 Support

- **Issues:** https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/issues
- **Discussions:** https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/discussions

## 📝 Changelog

### v1.0.0 (2025-10-07)
- Initial release
- Full HiveOS custom miner integration
- Auto-build Rust miner binary
- Real-time stats reporting
- Configurable via HiveOS Flight Sheets
- Support for custom node URLs and wallet addresses
- Multi-threaded mining support
- Comprehensive documentation

## 🙏 Credits

Built for the Xenom PoW blockchain community.

## 📄 License

Same as the Xenom project.

---

**Happy Mining! ⛏️**
