#!/bin/bash

# Waves PoW Node Startup Script with Java Module Fixes
# Fixes IllegalAccessError for Java 9+ module system

CONFIG_FILE="${1:-node/waves-pow.conf}"

java \
  --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
  --add-opens java.base/java.nio=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/sun.security.provider=ALL-UNNAMED \
  -jar node/target/waves-all-*.jar \
  "$CONFIG_FILE"
