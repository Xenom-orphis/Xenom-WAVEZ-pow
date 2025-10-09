#!/bin/bash
# Deploy updated node to remote server

REMOTE_HOST="eu.losmuchachos.digital"
REMOTE_USER="hainz"  # Change if needed
REMOTE_PATH="/home/hainz/Xenom-WAVEZ-pow"  # Change to actual path

echo "🚀 Deploying to $REMOTE_HOST..."

# SSH and deploy
ssh $REMOTE_USER@$REMOTE_HOST << 'ENDSSH'
cd /home/hainz/Xenom-WAVEZ-pow || exit 1

echo "📥 Pulling latest code..."
git fetch origin
git pull origin main

echo "🛑 Stopping node..."
pkill -f waves-all || echo "Node not running"
sleep 3

echo "🔨 Building node..."
sbt clean assembly

echo "🧹 Cleaning old data (optional - comment out if you want to keep blockchain)..."
 rm -rf ~/.waves-pow/data

echo "🚀 Starting node..."
nohup java -jar node/target/waves-all-*-DIRTY.jar node/waves-pow.conf > node.log 2>&1 &

echo "⏳ Waiting for node to start..."
sleep 10

echo "✅ Checking node status..."
curl -s http://localhost:36669/node/status | jq .

echo "📊 Checking if API supports miner address..."
curl -s "http://localhost:36669/mining/template?address=3MPxcxFTecdrN55McsYyEoWUnbRBR3v5rjh" | jq .miner_address

echo ""
echo "✅ Deployment complete!"
echo "📝 Check logs: tail -f node.log"
ENDSSH

echo ""
echo "🎉 Remote deployment finished!"
echo "Test mining: MINER_ADDRESS=3MPxcxFTecdrN55McsYyEoWUnbRBR3v5rjh NODE_URL=http://$REMOTE_HOST:36669 ./mine.sh"
