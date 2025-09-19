const operatingMode = Virtual.getHandle("enum:200");

function updateOperatingMode(result, error_code, error_message) {
  if (error_code === 0 && result && result.body) {
    try {
      let data = JSON.parse(result.body);
      print("Received data:", data);
      if (data.operating_mode !== undefined) {
        operatingMode.setValue(JSON.stringify(data.operating_mode));
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
