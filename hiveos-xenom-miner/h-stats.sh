#!/usr/bin/env bash

. `dirname $BASH_SOURCE`/h-manifest.conf

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

  # Get shares
  ac=$(grep -c "BLOCK ACCEPTED" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
  rj=$(grep -c "Solution rejected" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
  
  # Get GPU stats from HiveOS
  GPU_STATS_JSON=`cat $GPU_STATS_JSON 2>/dev/null`
  
  if [[ -n "$GPU_STATS_JSON" ]]; then
    # Extract GPU data
    gpu_temp=$(jq '.temp' <<< $GPU_STATS_JSON)
    gpu_fan=$(jq '.fan' <<< $GPU_STATS_JSON)
    gpu_bus=$(jq '.busids' <<< $GPU_STATS_JSON)
    
    # Count GPUs
    gpu_count=$(jq '.temp | length' <<< $GPU_STATS_JSON)
    
    # Calculate hashrate from GPU brute-force parameters
    # Format: "🚀 Starting GPU brute-force: 262144 threads, 2000 iterations each"
    threads=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ threads' | grep -oE '[0-9]+' | head -n 1)
    iterations=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ iterations' | grep -oE '[0-9]+' | head -n 1)
    
    if [[ -n "$threads" && -n "$iterations" && $gpu_count -gt 0 ]]; then
      # Total hashes per block attempt per GPU
      hashes_per_gpu=$(echo "$threads * $iterations" | bc)
      # Assume ~30 seconds per block attempt (adjust based on actual performance)
      hashrate_per_gpu=$(echo "scale=2; $hashes_per_gpu / 30 / 1000" | bc) # in kH/s
      total_khs=$(echo "scale=2; $hashrate_per_gpu * $gpu_count" | bc)
    else
      hashrate_per_gpu=0
      total_khs=0
    fi
    
    # Build per-GPU arrays
    for (( i=0; i < $gpu_count; i++ )); do
      hs[$i]=$hashrate_per_gpu
      temp[$i]=$(jq .[$i] <<< $gpu_temp)
      fan[$i]=$(jq .[$i] <<< $gpu_fan)
      busid=$(jq -r .[$i] <<< $gpu_bus)
      # Convert bus ID to decimal
      bus_numbers[$i]=`echo $busid | cut -d ":" -f1 | sed 's/^0*//' | awk '{ if ($1 == "") print 0; else printf "%d\n", ("0x"$1) }'`
    done
    
    khs=$total_khs
    
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
    # No GPU stats available
    stats=""
    khs=0
  fi
  
else
  # Log file too old
  stats=""
  khs=0
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"
