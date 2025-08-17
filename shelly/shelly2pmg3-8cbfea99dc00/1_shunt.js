// Shelly Script for Regulating Supply Temperature Based on Outdoor Temperature
//
// This script calculates a supply temperature setpoint using a simple heating curve:
//     T_sup = OFFSET + SLOPE * (T_outdoor_reference - T_outdoor)
// or a table/curve approach—whatever best fits your system.
//
// Key points:
//  - The script reads the current outdoor temperature (placeholder function).
//  - Applies a heating curve formula to compute the supply temperature.
//  - Clamps the resulting temperature to a min/max range to avoid extremes.
//  - Sends the new setpoint to the heating system.
//  - Runs whenever outdoor temperature changes.
//
// Adjust the constants, placeholder code, and the regulation interval for your setup.

// --- Constants and Configuration ---
const HEATING_SLOPE  = 1.1;      // Slope of the heating curve
const OFFSET         = 40.0;     // Base offset (°C)
const OUT_REF        = 5.0;      // Outdoor reference temperature (°C)
const MIN_SUPPLY     = 20.0;     // Minimum allowed supply temperature (°C)
const MAX_SUPPLY     = 60.0;     // Maximum allowed supply temperature (°C)

// desired supply temperature (°C)
const SetpointTemperature = Virtual.getHandle("number:201")

function getOutdoorTemperature() {
  return Shelly.getComponentStatus("bthomesensor:202").tC;
}

// --- Regulation Function ---
function regulateSupplyTemperature(T_outdoor) {
  print("Outdoor Temperature: " + T_outdoor + "°C")

  // Example of a simple linear heating curve:
  //   T_supply = OFFSET + SLOPE * (OUT_REF - T_outdoor)
  // Adjust or replace with a more advanced “curve” as needed.
  let T_supply = OFFSET + HEATING_SLOPE * (OUT_REF - T_outdoor);
  
  // Clamp to min/max values
  T_supply = Math.max(MIN_SUPPLY, Math.min(MAX_SUPPLY, T_supply));
  
  // Update the supply temperature setpoint
  SetpointTemperature.setValue(T_supply);
  print("Updated supply setpoint to: " + T_supply + "°C");
  
  // Trigger regulation of the shunt after updating setpoint
  regulate();
}

// Called on each Shelly event (avoid anonymous methods in shelly script)
function onEvent(event) {
  print(event)
  if (event.component === "bthomesensor:202") {
    const T_outdoor = event.info.tC
    regulateSupplyTemperature(T_outdoor)
  }
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
const FULL_MOVEMENT_TIME = 45; // time in s to move from fully closed (0%) to fully open (100%)

// Global variables to track the estimated shunt position (0-100%) and movement state.
// Assume initial position is fully open (100%).
const ShuntPosition = Virtual.getHandle("number:200")

function getPrimaryTemperature() {
  return Shelly.getComponentStatus("temperature:101").tC;
}

function getSupplyTemperature() {
  return Shelly.getComponentStatus("temperature:102").tC
}

function getReturnTemperature() {
  return Shelly.getComponentStatus("temperature:100").tC
}

// --- Regulation function ---
function regulate() {
  if (isMoving()) {
    print("Shunt is currently moving. Skipping regulation cycle.");
    return;
  }
  const T_setpoint = SetpointTemperature.getValue();
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

// Set up periodic regulation timer (reduced frequency since outdoor temp changes trigger regulation)
Timer.set(30000, true, regulate);
Shelly.addEventHandler(onEvent)
regulateSupplyTemperature(getOutdoorTemperature())

