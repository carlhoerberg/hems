// Shelly 1 Load Monitor Script
// Monitors Shelly Pro 3 EM phase currents and controls switch based on load

// Configuration
let CONFIG = {
  PRO3EM_IP: "shellypro3em-2cbcbba57ef8",  // Shelly Pro 3 EM hostname
  OWN_LOAD_CURRENT: 9,        // Current draw of this device's load in Amps
  MAX_PHASE_CURRENT: 22,       // Maximum allowed current per phase in Amps
  MIN_PHASE_VOLTAGE: 210,      // Minimum allowed voltage per phase in Volts
  MONITOR_INTERVAL: 1000,      // Monitoring interval in milliseconds (5 seconds)
  HTTP_TIMEOUT: 800           // HTTP request timeout in milliseconds
};

// Global variables
let monitorTimer = null;
let switchState = false;

// Function to get EM data from Shelly Pro 3 EM
function getEMData(callback) {
  Shelly.call("HTTP.GET", {
    url: "http://" + CONFIG.PRO3EM_IP + "/rpc/EM.GetStatus?id=0",
    timeout: CONFIG.HTTP_TIMEOUT
  }, function(response, error_code, error_message) {
    if (error_code !== 0) {
      print("HTTP Error:", error_code, error_message);
      callback(null);
      return;
    }
    
    try {
      let data = JSON.parse(response.body);
      callback(data);
    } catch (e) {
      print("JSON Parse Error:", e);
      callback(null);
    }
  });
}

// Function to check if load can be safely added
function canAddLoad(data) {
  if (!data) return false;
  
  let current_a = Math.abs(data.a_current || 0);
  let current_b = Math.abs(data.b_current || 0);
  let current_c = Math.abs(data.c_current || 0);
  
  let phase_a_total = current_a + CONFIG.OWN_LOAD_CURRENT;
  let phase_b_total = current_b + CONFIG.OWN_LOAD_CURRENT;
  let phase_c_total = current_c + CONFIG.OWN_LOAD_CURRENT;
  
  print("Phase currents - A:", current_a.toFixed(2), 
        "B:", current_b.toFixed(2), 
        "C:", current_c.toFixed(2));
  print("With load - A:", phase_a_total.toFixed(2), 
        "B:", phase_b_total.toFixed(2), 
        "C:", phase_c_total.toFixed(2));
  
  return (phase_a_total <= CONFIG.MAX_PHASE_CURRENT && 
          phase_b_total <= CONFIG.MAX_PHASE_CURRENT && 
          phase_c_total <= CONFIG.MAX_PHASE_CURRENT);
}

// Function to check for voltage drop
function hasVoltageDrop(data) {
  if (!data) return true; // Assume voltage drop if no data
  
  let voltage_a = Math.abs(data.a_voltage || 0);
  let voltage_b = Math.abs(data.b_voltage || 0);
  let voltage_c = Math.abs(data.c_voltage || 0);
  
  let voltageDrop = (voltage_a < CONFIG.MIN_PHASE_VOLTAGE ||
                     voltage_b < CONFIG.MIN_PHASE_VOLTAGE ||
                     voltage_c < CONFIG.MIN_PHASE_VOLTAGE);
  
  if (voltageDrop) {
    print("Phase voltages - A:", voltage_a.toFixed(1) + "V", 
          "B:", voltage_b.toFixed(1) + "V", 
          "C:", voltage_c.toFixed(1) + "V");
  }
  
  return voltageDrop;
}

// Function to control the switch
function controlSwitch(turnOn) {
  if (switchState === turnOn) return; // No change needed
  
  Shelly.call("Switch.Set", {
    id: 0,
    on: turnOn
  }, function(response, error_code, error_message) {
    if (error_code === 0) {
      switchState = turnOn;
      print("Switch turned", turnOn ? "ON" : "OFF");
    } else {
      print("Switch control error:", error_code, error_message);
    }
  });
}

// Main monitoring function
function monitorPhases() {
  getEMData(function(data) {
    if (data === null) {
      print("Failed to get EM data, turning off switch for safety");
      controlSwitch(false);
      return;
    }
    
    if (switchState) {
      // Switch is ON - check for voltage drop
      if (hasVoltageDrop(data)) {
        print("Voltage drop detected! Turning off switch");
        controlSwitch(false);
      }
    } else {
      // Switch is OFF - check if load can be added
      if (canAddLoad(data)) {
        print("Load can be safely added, turning on switch");
        controlSwitch(true);
      } else {
        print("Cannot turn on - would cause current overload or unsafe conditions");
      }
    }
  });
}

// Function to start monitoring
function startMonitoring() {
  if (monitorTimer !== null) return;
  
  print("Starting phase current monitoring");
  
  // Initial check
  monitorPhases();
  
  // Set up periodic monitoring
  monitorTimer = Timer.set(CONFIG.MONITOR_INTERVAL, true, monitorPhases);
}

// Function to stop monitoring
function stopMonitoring() {
  if (monitorTimer === null) return;
  
  print("Stopping phase current monitoring");
  
  // Clear timer
  Timer.clear(monitorTimer);
  monitorTimer = null;
  
  // Turn off switch
  controlSwitch(false);
}

// Input state change handler function
function inputStateHandler(event_data) {
  if (event_data.component === "input:0") {
    print("event", JSON.stringify(event_data))
    if (event_data.delta.state === true) {
      print("Input turned ON - starting monitoring");
      startMonitoring();
    } else if (event_data.delta.state === false) {
      print("Input turned OFF - stopping monitoring");
      stopMonitoring();
    }
  }
}

// Get current switch state on initialization
Shelly.call("Switch.GetStatus", {id: 0}, function(response, error_code, error_message) {
  if (error_code === 0) {
    switchState = response.output;
    print("Current switch state:", switchState ? "ON" : "OFF");
  }
});

// Get current input state on initialize
Shelly.call("Input.GetStatus", {id: 0}, function(response, error_code, error_message) {
  if (error_code === 0 && response.state === true) {
    print("Input is already ON at startup - starting monitoring");
    startMonitoring();
  } else {
    print("Input is OFF at startup");
    controlSwitch(false);
  }
});

// Event handler for input state changes
Shelly.addStatusHandler(inputStateHandler);

print("Shelly 1 Load Monitor Script initialized");
print("Configuration:");
print("- Pro 3 EM device:", CONFIG.PRO3EM_IP);
print("- Own load current:", CONFIG.OWN_LOAD_CURRENT, "A");
print("- Max phase current:", CONFIG.MAX_PHASE_CURRENT, "A");
print("- Min phase voltage:", CONFIG.MIN_PHASE_VOLTAGE, "V");
print("- Monitor interval:", CONFIG.MONITOR_INTERVAL, "ms");
