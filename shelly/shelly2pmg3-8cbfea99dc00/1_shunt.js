// Shelly Script for Regulating Supply Temperature Based on Supply Air Temperature
//
// This script maintains a constant supply air temperature of 18°C by regulating
// the shunt position based on the difference between actual and target supply air temperature.
//
// Key points:
//  - The script reads the current supply air temperature from the external API.
//  - Compares it with the target temperature (18°C).
//  - Adjusts the shunt position to maintain the desired supply air temperature.
//  - Runs periodically to ensure continuous regulation.
//
// Adjust the constants and regulation interval for your setup.

// --- Constants and Configuration ---
const TARGET_SUPPLY_AIR_TEMP = 17.0;  // Target supply air temperature (°C)
const MIN_SUPPLY     = 5.0;          // Minimum allowed supply temperature (°C)
const MAX_SUPPLY     = 60.0;          // Maximum allowed supply temperature (°C)
const SUPPLY_AIR_Kp  = 2.0;           // Proportional gain for supply air temperature control

// desired supply temperature (°C)
const SetpointTemperature = Virtual.getHandle("number:201")
const SupplyAirTemperature = Virtual.getHandle("number:202")

function calculateSupplyTemperature(callback) {
  fetchSupplyAirTemperature(function(T_supply_air, error) {
    if (error) {
      print("Failed to fetch supply air temperature: " + error);
      return;
    }

    print("Supply Air Temperature: " + T_supply_air + "°C (Target: " + TARGET_SUPPLY_AIR_TEMP + "°C)");

    // Calculate supply temperature based on supply air temperature error
    const airTempError = TARGET_SUPPLY_AIR_TEMP - T_supply_air;
    let T_supply = 20 + (SUPPLY_AIR_Kp * airTempError); // Base temperature + correction

    // Clamp to min/max values
    T_supply = Math.max(MIN_SUPPLY, Math.min(MAX_SUPPLY, T_supply));

    // Update the supply temperature setpoint
    SetpointTemperature.setValue(T_supply);
    print("Updated supply setpoint to: " + T_supply + "°C (Air temp error: " + airTempError.toFixed(1) + "°C)");

    callback(T_supply);
  });
}

// --- Shunt Control Integration ---
// This script regulates a mixing shunt in a heating system by controlling a cover mechanism.
// Since Cover.SetPosition isn’t available, we use Cover.Open and Cover.Close,
// and we estimate the cover position manually. Full travel (0% to 100%) takes 45 seconds.

// The algorithm computes an ideal valve (cover) position from:
//      T_set = T_return + x*(T_primary - T_return)
// i.e., x_ideal = (T_set - T_return) / (T_primary - T_return)
// Then a proportional correction is added based on the supply error.
// The desired cover position is compared with the estimated cover position,
// and if a difference exists beyond a small threshold, the cover is commanded
// to move in the appropriate direction for a calculated time.
//
// Constants
const Kp = 0.1;                // proportional gain (tune as needed)
const FULL_MOVEMENT_TIME = 90; // time in s to move from fully closed (0%) to fully open (100%)

// Global variables to track the estimated shunt position (0-100%) and movement state.
// Assume initial position is fully open (100%).
const ShuntPosition = Virtual.getHandle("number:200")

function getPrimaryTemperature() {
  return Shelly.getComponentStatus("temperature:100").tC;
}

function getSupplyTemperature() {
  return Shelly.getComponentStatus("temperature:102").tC
}

function getReturnTemperature() {
  return Shelly.getComponentStatus("temperature:101").tC
}

function fetchSupplyAirTemperature(callback) {
  Shelly.call("HTTP.GET", {
    url: "http://192.168.0.8/api/read_input?start_addr=6201",
    timeout: 10000,
  }, function(res, error_code, error_message) {
    if (error_code !== 0) {
      print("Error fetching supply air temperature: " + error_message);
      callback(null, error_message);
    } else {
      try {
        const response = JSON.parse(res.body);
        if (response.success && Array.isArray(response.data) && response.data.length > 0) {
          const tempValue = response.data[0] / 10.0; // Convert from 194 to 19.4°C
          SupplyAirTemperature.setValue(tempValue);
          callback(tempValue);
        } else {
          callback(null, "Invalid response format or API call failed");
        }
      } catch (e) {
        print("Error parsing supply air temperature response: " + e);
        callback(null, e);
      }
    }
  });
}

// --- Regulation function ---
function regulate() {
  if (isMoving()) {
    print("Shunt is currently moving. Skipping regulation cycle.");
    return;
  }

  calculateSupplyTemperature(function(T_setpoint) {
    const T_p = getPrimaryTemperature();
    const T_supply = getSupplyTemperature();
    const T_r = getReturnTemperature();

    let targetFraction = 0; // fraction from 0 (fully closed) to 1 (fully open)

    // Handle edge conditions to avoid division by zero
    if (Math.abs(T_p - T_r) < 0.1) {
      targetFraction = 1; // if there’s no temperature difference, default to open
    } else if (T_setpoint >= T_p) {
      targetFraction = 1;
    } else if (T_setpoint <= T_r) {
      targetFraction = 0;
    } else {
      targetFraction = (T_setpoint - T_r) / (T_p - T_r);
    }

    // Apply a proportional correction based on the supply error
    let error = T_setpoint - T_supply;
    let correction = Kp * error;

    let newFraction = targetFraction + correction;
    newFraction = Math.max(0, Math.min(1, newFraction));

    const desiredShuntPos = Math.round(newFraction * 100);
    //print("Primary: ", T_p, "°C, Supply: ", T_supply, "°C, Return: ", T_r, "°C, Setpoint: ", T_setpoint, "°C")

    if (desiredShuntPos === 100 && ShuntPosition.getValue() !== 100) {
      print("Opening shunt completely")
      Shelly.call("Cover.Open", { id: 0 }, function(res, error_code, error_message) {
        if (error_code !== 0) {
          print("Error issuing Cover.Open: " + error_message)
        } else {
          ShuntPosition.setValue(desiredShuntPos)
        }
      })
      return
    } else if (desiredShuntPos === 0 && ShuntPosition.getValue() !== 0) {
      print("Closing shunt completely")
      Shelly.call("Cover.Close", { id: 0 }, function(res, error_code, error_message) {
        if (error_code !== 0) {
          print("Error issuing Cover.Open: " + error_message)
        } else {
          ShuntPosition.setValue(desiredShuntPos)
        }
      })
      return
    }

    // Determine if movement is needed by comparing the desired shunt position with our estimated one.
    const diff = desiredShuntPos - ShuntPosition.getValue()

    // Calculate the movement time based on the difference.
    const movementFraction = Math.abs(diff) / 100;
    const movementTime = movementFraction * FULL_MOVEMENT_TIME; // in s

    if (Math.abs(diff) <= 2) {
      // print("Shunt position within threshold. No movement required.");
      return;
    }
    // Decide the command direction based on whether we need to open or close.
    const command = diff > 0 ? "Cover.Open" : "Cover.Close";
    print("Shunt position: ", ShuntPosition.getValue(), "%, Desired shunt position: ", desiredShuntPos, "% (Ideal: ", (targetFraction * 100).toFixed(1), "%, Correction: ", (correction * 100).toFixed(1), "%)")
    print("Issuing command: " + command + " for " + movementTime + "s, to new shunt position: " + desiredShuntPos + "%");

    // Issue the open or close command.
    Shelly.call(command, { id: 0, duration: movementTime }, function(res, error_code, error_message) {
      if (error_code !== 0) {
        print("Error issuing " + command + ": " + error_message)
      } else {
        // Update our estimated shunt position to the desired value.
        ShuntPosition.setValue(desiredShuntPos)
      }
    })
  })
}

function isMoving() {
  const coverState = Shelly.getComponentStatus("cover:0").state
  if (coverState === "opening" || coverState === "closing") {
    return true
  }
}

function resetShuntPosition() {
  const coverState = Shelly.getComponentStatus("cover:0").state
  if (coverState === "open") {
    ShuntPosition.setValue(100)
  } else if (coverState === "closed") {
    ShuntPosition.setValue(0)
  } else {
    Shelly.call("Cover.Open", { id: 0 })
    print("Reseting shunt position to fully open")
    ShuntPosition.setValue(100)
  }
}

// Initialize shunt position if needed
//resetShuntPosition()

// Set up periodic regulation timer
Timer.set(20000, true, regulate);
regulate(); // Initial call to set the first regulation

print("Heating regulation script initialized. Monitoring supply air temperature and regulating to maintain 18°C.");
