#!/usr/bin/env bash

set -euo pipefail

#
# upload_shelly_script.sh
#
# This script uploads a single JavaScript file to a Shelly device (Gen2) using "Script.PutCode".
# It stops the script if running, updates the code, and restarts if it was running.
#
# Directory Structure Example:
#   shelly-script-backup/hostname/0_myScript.js
# Usage Example:
#   ./upload_shelly_script.sh ./shelly-script-backup/hostname/0_myScript.js
#

# Ensure exactly one argument was passed
if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/<HOSTNAME>/<SCRIPT_ID>_<NAME>.js"
  exit 1
fi

SCRIPT_PATH="$1"

# Verify the file exists
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: File '$SCRIPT_PATH' not found."
  exit 1
fi

# Extract Shelly hostname from the parent directory name and construct FQDN
# e.g., if SCRIPT_PATH = .../hostname/0_myScript.js
device_dir=$(dirname "$SCRIPT_PATH")
shelly_hostname=$(basename "$device_dir")
shelly_fqdn="${shelly_hostname}.net.hallfjallet.se"

# Extract script ID from the filename (before the first underscore)
# e.g. "0_myScript.js" -> script_id=0
filename=$(basename "$SCRIPT_PATH")
script_id=$(echo "$filename" | cut -d'_' -f1)

echo "Detected Shelly hostname: $shelly_hostname"
echo "Resolved FQDN: $shelly_fqdn"
echo "Detected Script ID: $script_id"
echo "Script file path  : $SCRIPT_PATH"
echo "--------------------------------------------------"

# 1) Check if script is currently running (Script.GetStatus)
#    We parse .result.running (true/false)
is_running=$(curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  --data "$(jq -n --argjson scriptId "$script_id" '
    {
      "id": 1,
      "method": "Script.GetStatus",
      "params": {
        "id": $scriptId
      }
    }
  ')" \
  "http://${shelly_fqdn}/rpc" | jq -r '.result.running')

if [ "$is_running" = "true" ]; then
  echo "Script ID=$script_id is currently running; stopping it..."
  curl -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$(jq -n --argjson scriptId "$script_id" '
      {
        "id": 1,
        "method": "Script.Stop",
        "params": {
          "id": $scriptId
        }
      }
    ')" \
    "http://${shelly_fqdn}/rpc" >/dev/null
else
  echo "Script ID=$script_id is NOT running; no need to stop."
fi

# 2) Read the local script file content
script_code="$(cat "$SCRIPT_PATH")"

# 3) Upload script using chunked approach
script_size=$(wc -c < "$SCRIPT_PATH")
max_chunk_size=2048   # 2KB chunks

echo "Script size: $script_size bytes"
echo "Uploading script in chunks..."

# Always use chunked upload with while loop
offset=0
chunk_num=1

while [ $offset -lt "$script_size" ]; do
  remaining_size=$((script_size - offset))
  if [ $remaining_size -lt $max_chunk_size ]; then
    chunk_size=$remaining_size
  else
    chunk_size=$max_chunk_size
  fi
  
  chunk="$(echo -n "$script_code" | tail -c +$((offset+1)) | head -c $chunk_size)"
  
  echo "Uploading chunk $chunk_num (${chunk_size} bytes, offset ${offset})..."
  
  # Set append parameter based on chunk number
  if [ $chunk_num -eq 1 ]; then
    append_flag=false
  else
    append_flag=true
  fi
  
  response="$(curl -s \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$(jq -n --arg code "$chunk" --argjson scriptId "$script_id" --argjson append "$append_flag" '
      {
        "id": 1,
        "method": "Script.PutCode",
        "params": {
          "id": $scriptId,
          "code": $code,
          "append": $append
        }
      }
    ')" \
    "http://${shelly_fqdn}/rpc")"
  
  echo "Response: $response"
  #if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
  #  echo "Error uploading chunk $chunk_num:"
  #  echo "$response"
  #  exit 1
  #fi
  
  offset=$((offset + chunk_size))
  chunk_num=$((chunk_num + 1))
done

echo "Successfully uploaded script in $((chunk_num - 1)) chunks"

# 6) Generate random port for UDP logging
udp_port=$((1024 + RANDOM % 32767))
echo "Generated random UDP port: $udp_port"

# Configure UDP logging to random port
echo "Configuring UDP logging..."
curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg addr "192.168.51.2:$udp_port" '{
    "id": 1,
    "method": "Sys.SetConfig",
    "params": {
      "config": {
        "debug": {
          "udp": {
            "addr": $addr
          }
        }
      }
    }
  }')" \
  "http://${shelly_fqdn}/rpc" >/dev/null

echo "UDP logging configured to 192.168.51.2:$udp_port"

# 7) Start UDP server to receive log messages
echo "Starting UDP server on port $udp_port..."
echo "Listening for UDP logs from Shelly device..."
echo "Press Ctrl+C to stop"
echo "----------------------------------------"

# Use socat to listen for UDP messages
#socat UDP4-RECVFROM:$udp_port,fork SYSTEM:"sed -e a\\\\"
#nc --udp --listen "$udp_port" | while IFS= read -r line; do echo "$line"; done
socat -u UDP-RECVFROM:$udp_port,fork SYSTEM:"cat; echo" &

# 5) Always start the script after upload
echo "Starting script..."
curl -s \
  -X POST \
  -H "Content-Type: application/json" \
  --data "$(jq -n --argjson scriptId "$script_id" '
    {
      "id": 1,
      "method": "Script.Start",
      "params": {
        "id": $scriptId
      }
    }
  ')" \
  "http://${shelly_fqdn}/rpc" >/dev/null

echo "Done."

# Wait for the background socat process
wait
