// Motion-triggered lighting control driven by bthomesensor:200 status changes

let CONFIG = {
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

function setDimmersForMotion(motionDetected) {
  for (let i = 0; i < CONFIG.dimmers.length; i++) {
    let d = CONFIG.dimmers[i];
    let target = motionDetected ? d.brightLevel : d.dimLevel;

    const params = { id: d.id, on: target > 0, brightness: target }
    if (d.ip === undefined) {
      Shelly.call("light.set", params);
    } else {
      let url = "http://" + d.ip + "/rpc";
      let payload = { id: 1, method: "Light.Set", params: params };
      Shelly.call("HTTP.POST", { url: url, body: JSON.stringify(payload) }, function (res, code, msg) {
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

/* ---------- status handler ---------- */

console.log("Motion lighting started. Listening for bthomesensor:200 status changes");

Shelly.addStatusHandler(function (ev, _ud) {
  print(JSON.stringify(ev));
  
  // Handle bthomesensor:200 motion events
  if (ev && ev.component === "bthomesensor:200" && ev.name === "bthomesensor" && ev.id === 200) {
    if (ev.delta && typeof ev.delta.value === "boolean") {
      if (ev.delta.value) {
        handleMotionDetected();
      } else {
        handleNoMotion();
      }
    }
  }
});
