import json
import subprocess
import requests
import xml.etree.ElementTree as ET
import threading
import time
import sys
from prometheus_client import start_http_server, Gauge, Counter, CollectorRegistry, CONTENT_TYPE_LATEST

# --- STRICT CUSTOM REGISTRY ---
# Using a custom registry removes python_ and process_ metrics.
custom_registry = CollectorRegistry()

# --- CONFIGURATION ---
DONGLE_IP = "192.168.8.1"

# --- PROMETHEUS METRICS ---
# Bound only to the custom registry.
fuel_depth_cm = Gauge('fuel_tank_depth_cm', 'Distance to fuel surface', registry=custom_registry)
fuel_leak_alarm = Gauge('fuel_tank_leak_alarm', 'Bund leak detection (1=Alarm)', registry=custom_registry)
fuel_battery_low = Gauge('fuel_tank_battery_low', 'Sensor battery low (1=Low)', registry=custom_registry)

network_up_bytes = Counter('network_4g_upload_bytes_total', 'Total bytes uploaded', registry=custom_registry)
network_down_bytes = Counter('network_4g_download_bytes_total', 'Total bytes downloaded', registry=custom_registry)
network_time_seconds = Counter('network_4g_connect_time_seconds_total', 'Total connect time', registry=custom_registry)

network_rsrp = Gauge('network_4g_rsrp_dbm', 'RSRP strength', registry=custom_registry)
network_rsrq = Gauge('network_4g_rsrq_db', 'RSRQ quality', registry=custom_registry)
network_sinr = Gauge('network_4g_sinr_db', 'SINR ratio', registry=custom_registry)

# --- LOGIC ---

def parse_xml(text, unit):
    if text is None: return 0.0
    try:
        return float(text.replace(unit, ''))
    except:
        return 0.0

def fetch_dongle():
    url_traffic = f"http://{DONGLE_IP}/api/monitoring/traffic-statistics"
    url_signal = f"http://{DONGLE_IP}/api/device/signal"

    while True:
        try:
            # Traffic
            r = requests.get(url_traffic, timeout=5)
            if r.status_code == 200:
                root = ET.fromstring(r.text)
                # Manually setting internal value to avoid auto-increment logic
                network_up_bytes._value.set(float(root.find('TotalUpload').text))
                network_down_bytes._value.set(float(root.find('TotalDownload').text))
                network_time_seconds._value.set(float(root.find('TotalConnectTime').text))

            # Signal
            r = requests.get(url_signal, timeout=5)
            if r.status_code == 200:
                root = ET.fromstring(r.text)
                network_rsrp.set(parse_xml(root.find('rsrp').text, 'dBm'))
                network_rsrq.set(parse_xml(root.find('rsrq').text, 'dB'))
                network_sinr.set(parse_xml(root.find('sinr').text, 'dB'))
        except:
            pass
        time.sleep(30)

def run_radio():
    cmd = ['rtl_433', '-R', '43', '-F', 'json']
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        try:
            data = json.loads(line)
            depth = data.get('depth_cm')
            if depth is not None:
                fuel_depth_cm.set(depth)
                fuel_leak_alarm.set(data.get('leak', 0))
                if 'battery_ok' in data:
                    fuel_battery_low.set(0 if data['battery_ok'] else 1)
        except:
            continue

if __name__ == '__main__':
    # We disable OpenMetrics to get rid of the _created timestamps
    # Note: start_http_server handles the exposition.
    start_http_server(8000, registry=custom_registry)

    threading.Thread(target=fetch_dongle, daemon=True).start()

    try:
        run_radio()
    except KeyboardInterrupt:
        sys.exit(0)
