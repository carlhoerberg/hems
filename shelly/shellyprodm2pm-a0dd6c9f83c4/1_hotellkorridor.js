// Shelly script for motion-triggered lighting control

let CONFIG = {
  dimmers: [
    {
      id: 0, // Väggarmaturer
      brightLevel: 100,
      dimLevel: 30
    },
    {
      id: 1, // Infällda spotlights
      brightLevel: 100,
      dimLevel: 30
    }
  ],
  motionTimeout: 90000 // 60 seconds timeout (ms)
};

let motionTimer = null;

function setDimmersForMotion(motionDetected) {
  for (let i = 0; i < CONFIG.dimmers.length; i++) {
    let dimmer = CONFIG.dimmers[i];
    let targetLevel = motionDetected ? dimmer.brightLevel : dimmer.dimLevel;
    
    // Control local dimmer
    Shelly.call("light.set", {
      id: dimmer.id,
      on: targetLevel > 0,
      brightness: targetLevel
    });
  }
}

function handleMotionDetected() {
  console.log("Motion detected in hotel corridor - setting lights to 100%");
  setDimmersForMotion(true);
  
  // Clear existing timer
  if (motionTimer !== null) {
    Timer.clear(motionTimer);
  }
  
  // Set new timeout to dim lights to 30%
  motionTimer = Timer.set(CONFIG.motionTimeout, false, function() {
    console.log("Motion timeout - dimming lights to 30%");
    setDimmersForMotion(false);
    motionTimer = null;
  });
}

function handleNoMotion() {
  console.log("No motion detected - keeping current timer");
  // Motion stopped, but keep current timeout running
}

Shelly.addStatusHandler(function (ev, _ud) {
  // Handle bthomesensor:200 motion events
  if (ev && ev.component === "bthomesensor:200") {
    if (ev.delta && typeof ev.delta.value === "boolean") {
      if (ev.delta.value) {
        handleMotionDetected();
      } else {
        handleNoMotion();
      }
    }
  }
});

console.log("Hotel corridor motion lighting started. Listening for bthomesensor:200 status changes");
