const operatingMode = Virtual.getHandle("enum:200");
const fireplaceBool = Virtual.getHandle("boolean:200");

// Last value we pushed to (or read from) the virtual component. setValue() emits
// the "change" event asynchronously, so a boolean flag around the call is already
// reset when the handler runs. Compare against the known value instead.
let knownOperatingMode = null;
let knownFireplace = null;

function updateOperatingMode(result, error_code, error_message) {
  if (error_code === 0 && result && result.body) {
    try {
      const data = JSON.parse(result.body);
      const mode = data.data[0].toString();
      if (mode !== knownOperatingMode) {
        knownOperatingMode = mode;
        operatingMode.setValue(mode);
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
    url: "http://192.168.0.8/api/read_input?start_addr=6301"
  }, updateOperatingMode);
}

function onOperatingModeChange(ev) {
  if (ev.value === knownOperatingMode) return; // this update came from polling, not user action
  knownOperatingMode = ev.value;

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

// --- Fireplace mode ---
// Doc register 4x5002 (activation, write only) -> holding address 5001
// Doc register 3x6335 (status)                 -> input address 6334

function updateFireplaceStatus(result, error_code, error_message) {
  if (error_code === 0 && result && result.body) {
    try {
      const data = JSON.parse(result.body);
      const active = data.data[0] === 1;
      if (active !== knownFireplace) {
        knownFireplace = active;
        fireplaceBool.setValue(active);
      }
    } catch (e) {
      print("Error parsing fireplace status JSON:", e);
    }
  } else {
    print("Fireplace status HTTP request failed:", error_code, error_message);
  }
}

function pollFireplaceStatus() {
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.8/api/read_input?start_addr=6334"
  }, updateFireplaceStatus);
}

function onFireplaceChange(ev) {
  if (ev.value === knownFireplace) return; // this update came from polling, not user action
  knownFireplace = ev.value;

  const value = ev.value ? 1 : 0;
  print("Fireplace mode toggled to:", value);
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.8/api/write_multiple?start_addr=5001&values=" + value
  }, function(result, error_code, error_message) {
    if (error_code === 0) {
      print("Fireplace function set to:", value);
    } else {
      print("Failed to set fireplace function:", error_code, error_message);
    }
  });
}

operatingMode.on("change", onOperatingModeChange);
fireplaceBool.on("change", onFireplaceChange);

Timer.set(5000, true, pollOperatingMode);
Timer.set(5000, true, pollFireplaceStatus);

pollOperatingMode();
pollFireplaceStatus();
