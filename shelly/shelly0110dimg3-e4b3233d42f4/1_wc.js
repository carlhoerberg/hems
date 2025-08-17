// Shelly script for motion-triggered lighting control

let CONFIG = {
  motionDeviceMac: "38:39:8f:82:52:62",
  dimmers: [
    {
      id: 0,
      brightLevel: 40,
      dimLevel: 20
    },
    {
      ip: "shellyprodm2pm-a0dd6c9e5ea0", // Spottar
      id: 0,
      brightLevel: 100,
      dimLevel: 15
    },
    {
      ip: "shellyprodm2pm-a0dd6c9e5ea0", // Spegelarmatur
      id: 1,
      brightLevel: 100,
      dimLevel: 0
    },
    {
      ip: "shellyprodm1pm-34987aa90430", // Toalett väggarmatur
      id: 0,
      brightLevel: 100,
      dimLevel: 0
    }
  ],
  motionTimeout: 300000 // 5 minutes timeout (ms)
};

let motionTimer = null;

function setDimmersForMotion(motionDetected) {
  for (let i = 0; i < CONFIG.dimmers.length; i++) {
    let dimmer = CONFIG.dimmers[i];
    let targetLevel = motionDetected ? dimmer.brightLevel : dimmer.dimLevel;
    
    if (dimmer.ip === undefined) {
      // Control local dimmer
      Shelly.call("light.set", {
        id: dimmer.id,
        on: targetLevel > 0,
        brightness: targetLevel
      });
    } else {
      // Control remote dimmer via HTTP
      let url = "http://" + dimmer.ip + "/light/" + dimmer.id + "?turn=" + (targetLevel > 0 ? "on" : "off") + "&brightness=" + targetLevel;
      
      Shelly.call("HTTP.GET", {
        url: url
      }, function(result, error_code, error_message) {
        if (error_code !== 0) {
          console.log("Failed to control dimmer", dimmer.ip, ":", error_message);
        }
      });
    }
  }
}

function handleMotionDetected() {
  console.log("Motion detected - increasing brightness");
  setDimmersForMotion(true);
  
  // Clear existing timer
  if (motionTimer !== null) {
    Timer.clear(motionTimer);
  }
  
  // Set new timeout to dim lights
  motionTimer = Timer.set(CONFIG.motionTimeout, false, function() {
    console.log("Motion timeout - dimming lights");
    setDimmersForMotion(false);
    motionTimer = null;
  });
}

function handleNoMotion() {
  console.log("No motion detected - starting dim countdown");
  // Motion stopped, but keep current timeout running
}

// BLE scanner callback
function onBLEResult(ev, res) {
  if (res.addr === CONFIG.motionDeviceMac) {
    print(JSON.stringify(res));
    // Check for motion in advertisement data
    if (res.advData && res.advData.motion === true) {
      handleMotionDetected();
    } else if (res.advData && res.advData.motion === false) {
      handleNoMotion();
    }
  }
}

// Start BLE scanning
BLE.Scanner.Start({
  duration_ms: 0, // Continuous scanning
  interval_ms: 100
}, onBLEResult);

console.log("Motion lighting script started - monitoring device:", CONFIG.motionDeviceMac);
