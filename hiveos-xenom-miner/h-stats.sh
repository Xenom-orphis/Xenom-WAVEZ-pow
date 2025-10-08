#!/usr/bin/env bash
. `dirname $BASH_SOURCE`/h-manifest.conf

get_miner_uptime(){
  local a=0
  let a=`stat --format='%Y' ${CUSTOM_LOG_BASENAME}.log`-`stat --format='%Y' ${CUSTOM_CONFIG_FILENAME}`
  echo $a
}

get_log_time_diff(){
  local a=0
  let a=`date +%s`-`stat --format='%Y' ${CUSTOM_LOG_BASENAME}.log`
  echo $a
}

diffTime=$(get_log_time_diff)
maxDelay=250

if [ "$diffTime" -lt "$maxDelay" ]; then
  ver="$CUSTOM_VERSION"
  hs_units="khs"
  algo="xenom-pow"

  uptime=$(get_miner_uptime)
  [[ $uptime -lt 60 ]] && head -n 50 $CUSTOM_LOG_BASENAME.log > ${CUSTOM_LOG_BASENAME}_head.log

  # Get shares from log
  ac=$(grep -c "BLOCK ACCEPTED" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
  rj=$(grep -c "Solution rejected" ${CUSTOM_LOG_BASENAME}.log 2>/dev/null || echo 0)
  
  # Get GPU count and stats from HiveOS GPU_STATS_JSON
  GPU_STATS_JSON=`cat $GPU_STATS_JSON`
  
  # Fill arrays from gpu-stats
  temps=(`echo "$GPU_STATS_JSON" | jq -r ".temp[]"`)
  fans=(`echo "$GPU_STATS_JSON" | jq -r ".fan[]"`)
  busids=(`echo "$GPU_STATS_JSON" | jq -r ".busids[]"`)
  brands=(`echo "$GPU_STATS_JSON" | jq -r ".brand[]"`)
  
  gpu_count=${#busids[@]}
  indexes=()
  
  # Filter GPUs by nvidia brand
  for (( i=0; i < $gpu_count; i++)); do
    if [[ "${brands[$i]}" == "nvidia" ]]; then
      indexes+=($i)
      continue
    else
      unset temps[$i]
      unset fans[$i]
      unset busids[$i]
      unset brands[$i]
    fi
  done
  
  # Get GPU stats from HiveOS
  gpu_temp=$(jq '.temp' <<< $GPU_STATS_JSON)
  gpu_fan=$(jq '.fan' <<< $GPU_STATS_JSON)
  gpu_bus=$(jq '.busids' <<< $GPU_STATS_JSON)
  
  # Parse hashrate from log - look for "Total hashrate: X.XX MH/s"
  total_mhs=$(grep "Total hashrate:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
  
  # If not found, calculate from GPU brute-force info
  if [[ -z $total_mhs || $total_mhs == "0" ]]; then
    # Look for "Starting GPU brute-force: X threads, Y iterations each"
    threads=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ threads' | grep -oE '[0-9]+')
    iterations=$(grep "Starting GPU brute-force:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+ iterations' | grep -oE '[0-9]+')
    
    if [[ -n $threads && -n $iterations && $uptime -gt 0 ]]; then
      # Calculate total hashes: threads * iterations * gpu_count
      total_hashes=$(echo "$threads * $iterations * $gpu_count" | bc)
      # Estimate hashrate based on time (assume each block attempt takes ~30 seconds)
      # Count mining attempts in last 100 lines
      attempts=$(grep -c "Mining block" ${CUSTOM_LOG_BASENAME}.log | tail -n 100)
      if [[ $attempts -gt 0 ]]; then
        # Rough estimate: total_hashes per attempt / average time per attempt
        avg_time=30
        total_mhs=$(echo "scale=2; ($total_hashes / $avg_time) / 1000000" | bc 2>/dev/null || echo 0)
      fi
    fi
  fi
  
  [[ -z $total_mhs ]] && total_mhs=0
  
  # Get per-GPU hashrate from log
  per_gpu_mhs=$(grep "Per-GPU:" ${CUSTOM_LOG_BASENAME}.log | tail -n 1 | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
  
  # If no per-GPU hashrate found, divide total by GPU count
  if [[ -z $per_gpu_mhs || $per_gpu_mhs == "0" ]]; then
    if [[ $gpu_count -gt 0 && $(echo "$total_mhs > 0" | bc) -eq 1 ]]; then
      per_gpu_mhs=$(echo "scale=2; $total_mhs / $gpu_count" | bc 2>/dev/null || echo 0)
    else
      per_gpu_mhs=0
    fi
  fi
  
  # Convert MH/s to kH/s for total
  khs=$(echo "scale=2; $total_mhs * 1000" | bc 2>/dev/null || echo 0)
  
  # Build per-GPU arrays
  for (( i=0; i < ${gpu_count}; i++ )); do
    hs[$i]=$(echo "scale=2; $per_gpu_mhs * 1000" | bc 2>/dev/null || echo 0)
    temp[$i]=$(jq .[$i] <<< $gpu_temp)
    fan[$i]=$(jq .[$i] <<< $gpu_fan)
    busid=$(jq .[$i] <<< $gpu_bus)
    bus_numbers[$i]=`echo $busid | cut -d ":" -f1 | cut -c2- | awk -F: '{ printf "%d\n",("0x"$1) }'`
  done
  
  # Build stats JSON
  stats=$(jq -nc \
    --argjson hs "`echo ${hs[@]} | tr " " "\n" | jq -cs '.'`" \
    --argjson temp "`echo ${temp[@]} | tr " " "\n" | jq -cs '.'`" \
    --argjson fan "`echo ${fan[@]} | tr " " "\n" | jq -cs '.'`" \
    --arg hs_units "$hs_units" \
    --arg uptime "$uptime" \
    --arg ver "$ver" \
    --arg ac "$ac" \
    --arg rj "$rj" \
    --arg algo "$algo" \
    --argjson bus_numbers "`echo ${bus_numbers[@]} | tr " " "\n" | jq -cs '.'`" \
    '{$hs, $hs_units, $temp, $fan, $uptime, $ver, ar: [$ac, $rj], $algo, $bus_numbers}')

else
  stats=""
  khs=0
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"
