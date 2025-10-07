# 🎉 Xenom HiveOS Miner v1.0.0

First official release of the Xenom PoW miner for HiveOS!

## 🚀 Quick Start

```bash
# Download and install on your HiveOS rig
cd /tmp
wget https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/releases/download/v1.0.0/xenom-miner-1.0.0.tar.gz
tar -xzf xenom-miner-1.0.0.tar.gz -C /hive/miners/custom/
chmod +x /hive/miners/custom/xenom-miner/*.sh
ls -la /hive/miners/custom/xenom-miner/  # Verify
```

Then configure via HiveOS Dashboard:
- **Miner:** Custom → `xenom-miner`
- **Pool URL:** `http://eu.losmuchachos.digital:36669`
- **Wallet:** Your Xenom address

## ✨ Features

- ✅ Full HiveOS dashboard integration
- ✅ Real-time stats (hashrate, accepted/rejected blocks)
- ✅ Auto-builds Rust miner on first run
- ✅ Configurable via Flight Sheets
- ✅ Multi-threaded CPU mining
- ✅ Production-ready with error handling

## ⚙️ Configuration

**Basic:** Set pool URL and wallet in Flight Sheet

**Advanced:** Add to Extra Config (JSON):
```json
{
  "miner_address": "your_wallet",
  "threads": 0,
  "mv_len": 16
}
```

## 📊 What's Included

- Complete HiveOS integration scripts
- Mining loop with stats tracking
- Rust miner source code
- Comprehensive documentation (README, INSTALL, QUICKSTART)

## 📖 Documentation

See the included documentation files:
- `README.md` - Complete reference
- `INSTALL.md` - Step-by-step guide
- `QUICKSTART.md` - Fast deployment

## 🔧 Requirements

- HiveOS (latest version)
- Rust & Cargo (auto-installed if needed)
- Internet connection to Xenom node

## 📝 Changelog

### v1.0.0 (2025-10-07)
- Initial release
- Full HiveOS custom miner integration
- Auto-build support
- Real-time stats reporting
- Multi-threaded mining
- Comprehensive documentation

## 💬 Support

- **Issues:** [GitHub Issues](https://github.com/Xenom-orphis/Xenom-WAVEZ-pow/issues)
- **Logs:** `tail -f /var/log/miner/custom/xenom-miner/xenom.log`

---

**Happy Mining! ⛏️**
