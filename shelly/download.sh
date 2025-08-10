#!/usr/bin/env bash
#
# backup_shelly_scripts.sh
#
# This script takes multiple Shelly device hostnames as arguments,
# and for each hostname, it lists all available scripts and downloads
# their JS code for backup. Each device's scripts are stored in
# a subdirectory named after the hostname.
#
# Usage:
#   ./backup_shelly_scripts.sh <HOSTNAME_1> [<HOSTNAME_2> ... <HOSTNAME_N>]
#
# Example:
#   ./backup_shelly_scripts.sh shelly1 shelly2
#

# ------------- Configuration -------------
OUTPUT_DIR="./shelly"  # Base directory for backups
# ----------------------------------------

# Ensure at least one hostname argument is provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <HOSTNAME_1> [<HOSTNAME_2> ... <HOSTNAME_N>]"
  echo "Example: $0 shelly1 shelly2"
  exit 1
fi

# Create base output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

# Function to back up scripts from a single Shelly device
backup_shelly_scripts() {
  local SHELLY_HOSTNAME="$1"
  local SHELLY_FQDN="${SHELLY_HOSTNAME}.net.hallfjallet.se"
  echo "--------------------------------------------------"
  echo "Backing up scripts for Shelly @ ${SHELLY_FQDN}..."

  # Create a subdirectory for this device's scripts
  local DEVICE_DIR="${OUTPUT_DIR}/${SHELLY_HOSTNAME}"
  mkdir -p "${DEVICE_DIR}"

  # Fetch the list of scripts (declare + assign in one line)
  local scripts_json=$(curl -s "http://${SHELLY_FQDN}/rpc/Script.List")
  if [ -z "${scripts_json}" ] || [[ "${scripts_json}" == *"error"* ]]; then
    echo "  Error: Could not fetch script list from ${SHELLY_FQDN}. Response was:"
    echo "  ${scripts_json}"
    return 1
  fi

  # Parse the number of scripts (declare + assign in one line)
  local script_count=$(echo "${scripts_json}" | jq '.scripts | length')
  echo "  Found ${script_count} script(s) on ${SHELLY_FQDN}."

  if [ "${script_count}" -eq 0 ]; then
    echo "  No scripts to download for ${SHELLY_FQDN}."
    return 0
  fi

  # Iterate through each script, using 'jq' to parse JSON
  echo "${scripts_json}" | jq -c '.scripts[]' | while read -r script_info; do
    local script_id=$(echo "${script_info}" | jq -r '.id')
    local script_name=$(echo "${script_info}" | jq -r '.name')
    local safe_name=$(echo "${script_name}" | tr ' ' '_')

    # Get the script code directly from the "code" field
    local script_code=$(curl -s "http://${SHELLY_FQDN}/rpc/Script.GetCode?id=${script_id}" | jq -r '.data')

    local filename="${DEVICE_DIR}/${script_id}_${safe_name}.js"
    echo "${script_code}" > "${filename}"

    echo "    - Downloaded: Script ID=${script_id}, Name='${script_name}' → ${filename}"
  done

  echo "  Done backing up scripts for ${SHELLY_FQDN}."
}

# MAIN: Loop through all provided hostnames and back up scripts
for HOSTNAME in "$@"; do
  backup_shelly_scripts "${HOSTNAME}"
done

echo "--------------------------------------------------"
echo "All requested backups completed."
echo "Scripts are stored under '${OUTPUT_DIR}' in subdirectories per hostname."
