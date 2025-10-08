#!/usr/bin/env bash

cd `dirname $0`

# Set defaults if HiveOS variables are not set
if [[ -z $CUSTOM_CONFIG_FILENAME ]]; then
    CUSTOM_CONFIG_FILENAME="/hive/miners/custom/hiveos-xenom-miner/xenom.conf"
    echo "Using default config file: $CUSTOM_CONFIG_FILENAME"
fi

if [[ -z $CUSTOM_LOG_BASENAME ]]; then
    CUSTOM_LOG_BASENAME="/var/log/miner/custom/hiveos-xenom-miner/xenom"
    echo "Using default log file: $CUSTOM_LOG_BASENAME"
fi

[[ ! -f $CUSTOM_CONFIG_FILENAME ]] && echo -e "${RED}Custom config file $CUSTOM_CONFIG_FILENAME not found${NOCOLOR}" && exit 1

# Source the config
source $CUSTOM_CONFIG_FILENAME

MINER_DIR=$(dirname $CUSTOM_CONFIG_FILENAME)
MINER_BIN="$MINER_DIR/bin/xenom-miner-rust"
LOG_FILE="${CUSTOM_LOG_BASENAME}.log"

# Create log directory
mkdir -p $(dirname $LOG_FILE)

# Check if miner binary exists
if [ ! -f "$MINER_BIN" ]; then
    echo "❌ Error: Miner binary not found at $MINER_BIN" | tee -a $LOG_FILE
    echo "Please ensure the package was extracted correctly." | tee -a $LOG_FILE
    exit 1
fi

# Show configuration
echo "=== Xenom Miner Starting ===" | tee -a $LOG_FILE
echo "Node URL: $NODE_URL" | tee -a $LOG_FILE
echo "Miner Address: ${MINER_ADDRESS:-Node wallet (default)}" | tee -a $LOG_FILE
echo "Threads: $THREADS" | tee -a $LOG_FILE
echo "MV Length: $MV_LEN" | tee -a $LOG_FILE
echo "GPU Enabled: ${USE_GPU:-false}" | tee -a $LOG_FILE
if [ "${USE_GPU}" = "true" ]; then
    echo "GPU ID: ${GPU_ID:-0}" | tee -a $LOG_FILE
    echo "Multi-GPU: ${MULTI_GPU:-false}" | tee -a $LOG_FILE
    echo "GPU Batches: ${GPU_BATCHES:-40000}" | tee -a $LOG_FILE
fi
echo "===========================" | tee -a $LOG_FILE

# Export variables for the mining script
export NODE_URL
export MINER_ADDRESS
export MINER_BIN
export THREADS
export MV_LEN
export USE_GPU
export GPU_ID
export MULTI_GPU
export GPU_BATCHES

# Run the mining loop
exec $MINER_DIR/mine-loop.sh 2>&1 | tee -a $LOG_FILE
