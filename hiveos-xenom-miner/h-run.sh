#!/usr/bin/env bash

cd `dirname $0`

# Set defaults if HiveOS variables are not set
if [[ -z $CUSTOM_CONFIG_FILENAME ]]; then
    CUSTOM_CONFIG_FILENAME="/hive/miners/custom/xenom-miner/xenom.conf"
    echo "Using default config file: $CUSTOM_CONFIG_FILENAME"
fi

if [[ -z $CUSTOM_LOG_BASENAME ]]; then
    CUSTOM_LOG_BASENAME="/var/log/miner/custom/xenom-miner/xenom"
    echo "Using default log file: $CUSTOM_LOG_BASENAME"
fi

[[ ! -f $CUSTOM_CONFIG_FILENAME ]] && echo -e "${RED}Custom config file $CUSTOM_CONFIG_FILENAME not found${NOCOLOR}" && exit 1

# Source the config
source $CUSTOM_CONFIG_FILENAME

MINER_DIR=$(dirname $CUSTOM_CONFIG_FILENAME)
MINER_BIN="$MINER_DIR/xenom-miner-rust/target/release/xenom-miner-rust"
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"

# Create log directory
mkdir -p $(dirname $LOG_FILE)

# Check if miner binary exists, if not build it
if [ ! -f "$MINER_BIN" ]; then
    echo "Building Xenom miner..." | tee -a $LOG_FILE
    cd $MINER_DIR/xenom-miner-rust
    cargo build --release 2>&1 | tee -a $LOG_FILE
    cd $MINER_DIR
    
    if [ ! -f "$MINER_BIN" ]; then
        echo "Failed to build miner binary" | tee -a $LOG_FILE
        exit 1
    fi
fi

# Show configuration
echo "=== Xenom Miner Starting ===" | tee -a $LOG_FILE
echo "Node URL: $NODE_URL" | tee -a $LOG_FILE
echo "Miner Address: ${MINER_ADDRESS:-Node wallet (default)}" | tee -a $LOG_FILE
echo "Threads: $THREADS" | tee -a $LOG_FILE
echo "MV Length: $MV_LEN" | tee -a $LOG_FILE
echo "===========================" | tee -a $LOG_FILE

# Export variables for the mining script
export NODE_URL
export MINER_ADDRESS
export MINER_BIN
export THREADS
export MV_LEN

# Run the mining loop
exec $MINER_DIR/mine-loop.sh 2>&1 | tee -a $LOG_FILE
