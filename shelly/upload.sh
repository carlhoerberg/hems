#!/usr/bin/env bash
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

# 2) Read the local script file content (no manual escaping)
script_code="$(cat "$SCRIPT_PATH")"

# 3) Generate JSON payload for "Script.PutCode" using jq
json_payload="$(jq -n \
  --arg code "$script_code" \
  --argjson scriptId "$script_id" '
  {
    "id": 1,
    "method": "Script.PutCode",
    "params": {
      "id": $scriptId,
      "code": $code
    }
  }
')"

echo "Uploading new code to Shelly device @ $shelly_fqdn ..."

# 4) Perform the upload (PutCode)
response="$(curl -s -i\
  -X POST \
  -H "Content-Type: application/json" \
  --data "${json_payload}" \
  "http://${shelly_fqdn}/rpc")"

# Check for errors in the response
if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
  echo "Error response from device:"
  echo "$response"
  exit 1
else
  echo "Successfully uploaded new code for Script ID=$script_id"
  echo "$response"
fi

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
socat UDP4-LISTEN:$udp_port,fork -

echo "Done."

