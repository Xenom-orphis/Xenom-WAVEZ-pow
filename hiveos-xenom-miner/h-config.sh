#!/usr/bin/env bash
# This script generates the miner configuration file
# HiveOS variables available: $CUSTOM_URL, $CUSTOM_TEMPLATE, $CUSTOM_USER_CONFIG, etc.

# Set default config filename if not provided by HiveOS
if [[ -z $CUSTOM_CONFIG_FILENAME ]]; then
    CUSTOM_CONFIG_FILENAME="/hive/miners/custom/xenom-miner/xenom.conf"
    echo "Using default config file: $CUSTOM_CONFIG_FILENAME"
fi

[[ -z $CUSTOM_URL ]] && echo -e "${YELLOW}CUSTOM_URL is empty${NOCOLOR}" && return 1

# Parse pool URL (node URL)
NODE_URL="$CUSTOM_URL"

# Get miner address from template or user config
MINER_ADDRESS=""
if [[ ! -z $CUSTOM_TEMPLATE ]]; then
    MINER_ADDRESS="$CUSTOM_TEMPLATE"
fi

# User config can override settings (JSON format expected)
if [[ ! -z $CUSTOM_USER_CONFIG ]]; then
    # Try to parse JSON user config
    MINER_ADDRESS=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.miner_address // empty' 2>/dev/null)
    [[ -z $MINER_ADDRESS ]] && MINER_ADDRESS=$(echo "$CUSTOM_USER_CONFIG" | jq -r '.address // empty' 2>/dev/null)
fi

# Create config file
cat > $CUSTOM_CONFIG_FILENAME <<EOF
# Xenom Miner Configuration
NODE_URL=$NODE_URL
MINER_ADDRESS=$MINER_ADDRESS
THREADS=0
MV_LEN=16
EOF

echo "Xenom miner config generated:"
cat $CUSTOM_CONFIG_FILENAME
