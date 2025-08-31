// Motion-triggered lighting control driven by events from ble-shelly-blu

let CONFIG = {
  // BLU device to react to (case-insensitive)
  motionDeviceMac: "38:39:8f:82:52:62",

  // Event name used by the ble-shelly-blu emitter
  bluEventName: "shelly-blu",

  dimmers: [
    { id: 0, brightLevel: 40, dimLevel: 20 },
    { ip: "shellyprodm2pm-a0dd6c9e5ea0", id: 0, brightLevel: 100, dimLevel: 15 }, // Spottar
    { ip: "shellyprodm2pm-a0dd6c9e5ea0", id: 1, brightLevel: 100, dimLevel: 0  }, // Spegelarmatur
    { ip: "shellyprodm1pm-34987aa90430", id: 0, brightLevel: 100, dimLevel: 20  }  // Toalett väggarmatur
  ],

  // 5 minutes (ms)
  motionTimeout: 300000
};

let motionTimer = null;

/* ---------- helpers ---------- */
function normMac(s) { return (s || "").toLowerCase(); }

function motionToBool(value) {
  // motion may be: 1/0, true/false, or an array of those
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) {
      if (value[i] === 1 || value[i] === true) return true;
    }
    return false;
  }
  return (value === 1 || value === true);
}

function setDimmersForMotion(motionDetected) {
  for (let i = 0; i < CONFIG.dimmers.length; i++) {
    let d = CONFIG.dimmers[i];
    let target = motionDetected ? d.brightLevel : d.dimLevel;

    if (d.ip === undefined) {
      Shelly.call("light.set", { id: d.id, on: target > 0, brightness: target });
    } else {
      let url = "http://" + d.ip + "/light/" + d.id +
        "?turn=" + (target > 0 ? "on" : "off") +
        "&brightness=" + target;

      Shelly.call("HTTP.GET", { url: url }, function (res, code, msg) {
        if (code !== 0) console.log("Failed to control dimmer", d.ip, ":", msg);
      });
    }
  }
}

function handleMotionDetected() {
  console.log("Motion detected - increasing brightness");
  setDimmersForMotion(true);

  if (motionTimer !== null) Timer.clear(motionTimer);

  motionTimer = Timer.set(CONFIG.motionTimeout, false, function () {
    console.log("Motion timeout - dimming lights");
    setDimmersForMotion(false);
    motionTimer = null;
  });
}

function handleNoMotion() {
  // Do not reset the timer; simply let it count down
  console.log("No motion - countdown continues");
}

/* ---------- event-driven part ---------- */
// ble-shelly-blu emits events via Shelly.emitEvent(CONFIG.eventName, data)
// We subscribe to all events and filter by name + MAC.
function onEvent(ev, _ud) {
  print(JSON.stringify(ev))
  if (!ev || ev.event !== CONFIG.bluEventName) return;

  let data = ev.data || {};

  // Basic sanity: make sure this is BTHome v2 payload with an address
  if (typeof data.address === "undefined" || data.BTHome_version !== 2) return;

  if (normMac(data.address) !== normMac(CONFIG.motionDeviceMac)) return;

  // Per your typedef, motion can be number or number[]
  if (typeof data.motion === "undefined") {
    // Some BLU variants might use different keys; add quick fallbacks if you ever need them:
    // if (typeof data.pir !== "undefined") data.motion = data.pir;
    // else if (typeof data.moving !== "undefined") data.motion = data.moving;
    console.log("BLU event for device but no 'motion' field:", JSON.stringify(data));
    return;
  }

  if (motionToBool(data.motion)) {
    handleMotionDetected();
  } else {
    handleNoMotion();
  }
}

// Subscribe once; no BLE scanning here — we rely entirely on the emitter script
Shelly.addEventHandler(onEvent);

console.log(
  "Motion lighting (event-driven) started. Listening for '%s' from %s",
  CONFIG.bluEventName,
  CONFIG.motionDeviceMac
);
