#!/bin/bash

# Waves PoW Peer Node Startup Script with Java Module Fixes

java \
  --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
  --add-opens java.base/java.nio=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/sun.security.provider=ALL-UNNAMED \
  -jar node/target/waves-all-*.jar \
  node/waves-pow-peer.conf
