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

function pollEnvistarStatus() {
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.2:8000/envistar/status"
  }, updateOperatingMode);
}

Timer.set(5000, true, pollEnvistarStatus);
pollEnvistarStatus();
