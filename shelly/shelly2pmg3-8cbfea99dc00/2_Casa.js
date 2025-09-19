const operatingMode = Virtual.getHandle("enum:200");

function updateOperatingMode(result, error_code, error_message) {
  if (error_code === 0 && result && result.body) {
    try {
      const data = JSON.parse(result.body);
      if (data.operating_mode !== undefined) {
        operatingMode.setValue(data.operating_mode.toString());
      }
    } catch (e) {
      print("Error parsing JSON:", e);
    }
  } else {
    print("HTTP request failed:", error_code, error_message);
  }
}

function pollOperatingMode() {
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.8/api/read_holding?start_addr=5000"
  }, updateOperatingMode);
}

function onOperatingModeChange(ev) {
  print("Operating mode changed to:", ev.value);
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.8/api/write_multiple?start_addr=5000&values=" + ev.value,
  }, function(result, error_code, error_message) {
    if (error_code === 0) {
      print("Successfully set operating mode to:", ev.value);
    } else {
      print("Failed to set operating mode:", error_code, error_message);
    }
  });
}

operatingMode.on("change", onOperatingModeChange)
Timer.set(5000, true, pollOperatingMode);
pollOperatingMode();
