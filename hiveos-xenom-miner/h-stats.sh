#!/usr/bin/env bash

. `dirname $BASH_SOURCE`/h-manifest.conf

# API port (default: 3333)
API_PORT=${API_PORT:-3333}
API_URL="http://localhost:${API_PORT}/stats"

# Try to get stats from miner API
MINER_STATS=$(curl -s --connect-timeout 2 "$API_URL" 2>/dev/null)

if [[ -n "$MINER_STATS" && "$MINER_STATS" != "null" ]]; then
  # Successfully got stats from API
  ver=$(echo "$MINER_STATS" | jq -r '.version' 2>/dev/null || echo "$CUSTOM_VERSION")
  hs_units="mhs"  # Miner reports in MH/s
  algo="xenom-pow"
  
  # Extract stats from API response
  uptime=$(echo "$MINER_STATS" | jq -r '.uptime_secs' 2>/dev/null || echo 0)
  ac=$(echo "$MINER_STATS" | jq -r '.accepted_shares' 2>/dev/null || echo 0)
  rj=$(echo "$MINER_STATS" | jq -r '.rejected_shares' 2>/dev/null || echo 0)
  gpu_count=$(echo "$MINER_STATS" | jq -r '.gpu_count' 2>/dev/null || echo 0)
  total_mhs=$(echo "$MINER_STATS" | jq -r '.hashrate_mhs' 2>/dev/null || echo 0)
  
  # Get GPU stats from HiveOS
  GPU_STATS_JSON=`cat $GPU_STATS_JSON 2>/dev/null`
  
  if [[ -n "$GPU_STATS_JSON" && $gpu_count -gt 0 ]]; then
    # Extract GPU hardware data (temp, fan, bus)
    gpu_temp=$(jq '.temp' <<< $GPU_STATS_JSON)
    gpu_fan=$(jq '.fan' <<< $GPU_STATS_JSON)
    gpu_bus=$(jq '.busids' <<< $GPU_STATS_JSON)
    
    # Get per-GPU hashrates from miner API
    per_gpu_hashrates=$(echo "$MINER_STATS" | jq -r '.per_gpu_hashrate_mhs' 2>/dev/null)
    
    # Build per-GPU arrays
    for (( i=0; i < $gpu_count; i++ )); do
      # Get hashrate for this GPU from API
      hs[$i]=$(echo "$per_gpu_hashrates" | jq -r ".[$i]" 2>/dev/null || echo 0)
      temp[$i]=$(jq .[$i] <<< $gpu_temp)
      fan[$i]=$(jq -r .[$i] <<< $gpu_fan)
      busid=$(jq -r .[$i] <<< $gpu_bus)
      # Convert bus ID to decimal
      bus_numbers[$i]=`echo $busid | cut -d ":" -f1 | sed 's/^0*//' | awk '{ if ($1 == "") print 0; else printf "%d\n", ("0x"$1) }'`
    done
    
    khs=$(echo "scale=2; $total_mhs * 1000" | bc)  # Convert MH/s to kH/s for HiveOS
    
    # Build stats JSON
    stats=$(jq -nc \
      --argjson hs "`echo ${hs[@]} | tr ' ' '\n' | jq -cs '.'`" \
      --argjson temp "`echo ${temp[@]} | tr ' ' '\n' | jq -cs '.'`" \
      --argjson fan "`echo ${fan[@]} | tr ' ' '\n' | jq -cs '.'`" \
      --argjson bus_numbers "`echo ${bus_numbers[@]} | tr ' ' '\n' | jq -cs '.'`" \
      --arg hs_units "$hs_units" \
      --arg uptime "$uptime" \
      --arg ver "$ver" \
      --arg ac "$ac" \
      --arg rj "$rj" \
      --arg algo "$algo" \
      '{$hs, $hs_units, $temp, $fan, $uptime, $ver, ar: [$ac, $rj], $algo, $bus_numbers}')
  else
    # No GPU hardware stats available, use API data only
    khs=$(echo "scale=2; $total_mhs * 1000" | bc)
    stats=$(jq -nc \
      --arg hs_units "$hs_units" \
      --arg uptime "$uptime" \
      --arg ver "$ver" \
      --arg ac "$ac" \
      --arg rj "$rj" \
      --arg algo "$algo" \
      --arg khs "$khs" \
      '{hs: [$khs], $hs_units, $uptime, $ver, ar: [$ac, $rj], $algo}')
  fi
  
else
  # API not available, fallback to log parsing (legacy method)
  get_miner_uptime(){
    local a=0
    let a=`stat --format='%Y' ${CUSTOM_LOG_BASENAME}.log`-`stat --format='%Y' ${CUSTOM_CONFIG_FILENAME}` 2>/dev/null || echo 0
    echo $a
  }

  get_log_time_diff(){
    local a=0
    let a=`date +%s`-`stat --format='%Y' ${CUSTOM_LOG_BASENAME}.log` 2>/dev/null || echo 0
    echo $a
  }

  diffTime=$(get_log_time_diff)
  maxDelay=250

  if [ "$diffTime" -lt "$maxDelay" ]; then
    ver="$CUSTOM_VERSION"
    hs_units="khs"
    algo="xenom-pow"
    
    uptime=$(get_miner_uptime)
    [[ $uptime -lt 60 ]] && head -n 50 $CUSTOM_LOG_BASENAME.log > ${CUSTOM_LOG_BASENAME}_head.log 2>/dev/null

    # Get shares from logs
    ac=$(grep -c "BLOCK ACCEPTED" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
    rj=$(grep -c "Solution rejected" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
    
    # Get GPU stats from HiveOS
    GPU_STATS_JSON=`cat $GPU_STATS_JSON 2>/dev/null`
    
    if [[ -n "$GPU_STATS_JSON" ]]; then
      gpu_temp=$(jq '.temp' <<< $GPU_STATS_JSON)
      gpu_fan=$(jq '.fan' <<< $GPU_STATS_JSON)
      gpu_bus=$(jq '.busids' <<< $GPU_STATS_JSON)
      gpu_count=$(jq '.temp | length' <<< $GPU_STATS_JSON)
      
      # Estimate hashrate from logs
      threads=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ threads' | grep -oE '[0-9]+' | head -n 1)
      iterations=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ iterations' | grep -oE '[0-9]+' | head -n 1)
      
      if [[ -n "$threads" && -n "$iterations" && $gpu_count -gt 0 ]]; then
        hashes_per_gpu=$(echo "$threads * $iterations" | bc)
        hashrate_per_gpu=$(echo "scale=2; $hashes_per_gpu / 30 / 1000" | bc)
        total_khs=$(echo "scale=2; $hashrate_per_gpu * $gpu_count" | bc)
      else
        hashrate_per_gpu=0
        total_khs=0
      fi
      
      for (( i=0; i < $gpu_count; i++ )); do
        hs[$i]=$hashrate_per_gpu
        temp[$i]=$(jq .[$i] <<< $gpu_temp)
        fan[$i]=$(jq -r .[$i] <<< $gpu_fan)
        busid=$(jq -r .[$i] <<< $gpu_bus)
        bus_numbers[$i]=`echo $busid | cut -d ":" -f1 | sed 's/^0*//' | awk '{ if ($1 == "") print 0; else printf "%d\n", ("0x"$1) }'`
      done
      
      khs=$total_khs
      
      stats=$(jq -nc \
        --argjson hs "`echo ${hs[@]} | tr ' ' '\n' | jq -cs '.'`" \
        --argjson temp "`echo ${temp[@]} | tr ' ' '\n' | jq -cs '.'`" \
        --argjson fan "`echo ${fan[@]} | tr ' ' '\n' | jq -cs '.'`" \
        --argjson bus_numbers "`echo ${bus_numbers[@]} | tr ' ' '\n' | jq -cs '.'`" \
        --arg hs_units "$hs_units" \
        --arg uptime "$uptime" \
        --arg ver "$ver" \
        --arg ac "$ac" \
        --arg rj "$rj" \
        --arg algo "$algo" \
        '{$hs, $hs_units, $temp, $fan, $uptime, $ver, ar: [$ac, $rj], $algo, $bus_numbers}')
    else
      stats=""
      khs=0
    fi
  else
    stats=""
    khs=0
  fi
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"
