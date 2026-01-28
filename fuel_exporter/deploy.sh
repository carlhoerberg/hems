#!/bin/bash
# shellcheck disable=SC2029
set -e

HOST="lifthuset"
REMOTE_DIR="/opt/fuel_monitor"
SERVICE_NAME="fuel-exporter"

if [ "$1" = "--bootstrap" ]; then
    echo "Bootstrapping $HOST..."

    # Install system dependencies
    ssh "$HOST" "sudo apt-get update && sudo apt-get install -y python3-venv rtl-433"

    # Create remote directory
    ssh "$HOST" "sudo mkdir -p $REMOTE_DIR"

    # Initialize virtual environment
    ssh "$HOST" "sudo python3 -m venv $REMOTE_DIR/venv"

    # Install Python dependencies
    ssh "$HOST" "sudo $REMOTE_DIR/venv/bin/pip install -q prometheus_client requests"

    echo "Bootstrap complete."
fi

echo "Deploying to $HOST..."

# Copy the exporter script
scp fuel_exporter.py "$HOST:/tmp/"
ssh "$HOST" "sudo mv /tmp/fuel_exporter.py $REMOTE_DIR/"

# Copy and install the service file
scp fuel-exporter.service "$HOST:/tmp/"
ssh "$HOST" "sudo mv /tmp/fuel-exporter.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl restart $SERVICE_NAME"

echo "Done. Service status:"
ssh "$HOST" "systemctl status $SERVICE_NAME --no-pager"
