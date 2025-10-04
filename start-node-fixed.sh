#!/bin/bash
# Start Xenom node with Java module access fixes

# Find the JAR file
JAR_FILE=$(ls node/target/scala-2.13/waves-all-*.jar 2>/dev/null | head -n1)

if [ -z "$JAR_FILE" ]; then
    echo "❌ Node JAR not found. Build it first with: sbt node/assembly"
    exit 1
fi

echo "🚀 Starting Xenom node with Java module fixes..."
echo "   JAR: $JAR_FILE"
echo ""

# Start with Java module access flags for Java 11+
exec java \
    --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
    --add-opens java.base/java.nio=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    -Xmx4g \
    -jar "$JAR_FILE" \
    node/xenom-testnet.conf
