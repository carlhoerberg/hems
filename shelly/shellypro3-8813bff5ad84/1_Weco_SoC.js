// ============================================================
// weco_soc_poller.js
// Polls http://<host>:8000/weco and pushes soc_value, sys_vol and
// current for each battery pack into pre-created Shelly Virtual
// Number components, so they show up (read-only) in the Shelly
// Cloud UI.
//
// Setup required before running:
//   1. Create THREE "Number" virtual components per weco unit
//      (Settings -> Virtual Components -> Add Component -> Number)
//      and note their numeric ids.
//   2. Fill in VC_MAP below, one entry per weco unit, IN THE SAME
//      ORDER as the /weco JSON array (index 0 = first unit, etc).
// ============================================================

// ---- CONFIG ------------------------------------------------
var POLL_URL = "http://192.168.0.2:8000/weco";
var POLL_INTERVAL_MS = 5000; // how often to poll, in ms

// One entry per weco unit, in array order. Replace the ids with
// your actual virtual Number component ids.
var VC_MAP = [
  { soc: 200, sys_vol: 204, current: 202 }, // unit 0
  { soc: 201, sys_vol: 205, current: 203 }  // unit 1
];
// --------------------------------------------------------------

// Resolve handles once at startup. getHandle()/setValue() are
// local synchronous calls - not RPCs - so there's no "too many
// calls in progress" limit to worry about here.
var VC_HANDLES = [];

function initHandles() {
  var i;
  for (i = 0; i < VC_MAP.length; i++) {
    var ids = VC_MAP[i];
    VC_HANDLES.push({
      soc: Virtual.getHandle("number:" + ids.soc),
      sys_vol: Virtual.getHandle("number:" + ids.sys_vol),
      current: Virtual.getHandle("number:" + ids.current)
    });
  }
}

function setIfNumber(handle, value, label, idx) {
  if (!handle) {
    print("weco: no handle for unit " + idx + " (" + label + ") - check VC_MAP");
    return;
  }
  if (typeof value === "number") {
    handle.setValue(value);
  } else {
    print("weco: unit " + idx + " missing " + label);
  }
}

function handleResponse(result, error_code, error_message) {
  if (error_code !== 0) {
    print("weco: HTTP.GET error: " + error_message);
    return;
  }

  if (!result || typeof result.body !== "string") {
    print("weco: empty/invalid response");
    return;
  }

  var data = null;
  try {
    data = JSON.parse(result.body);
  } catch (e) {
    print("weco: JSON parse failed");
    return;
  }

  if (typeof data !== "object" || typeof data.length !== "number") {
    print("weco: unexpected payload shape");
    return;
  }

  var n = data.length;
  var i;
  for (i = 0; i < n; i++) {
    if (i >= VC_HANDLES.length) {
      // more units than configured virtual components; ignore extras
      break;
    }
    var unit = data[i];
    var handles = VC_HANDLES[i];

    if (!unit) {
      print("weco: unit " + i + " missing from payload");
      continue;
    }

    setIfNumber(handles.soc, unit.soc_value, "soc_value", i);
    setIfNumber(handles.sys_vol, unit.sys_vol, "sys_vol", i);
    setIfNumber(handles.current, unit.current * 6, "current", i);
  }
}

function pollWeco() {
  Shelly.call(
    "HTTP.GET",
    { url: POLL_URL, timeout: 5 },
    handleResponse
  );
}

// Set up handles once, then run immediately and on a repeating timer
initHandles();
pollWeco();
Timer.set(POLL_INTERVAL_MS, true, pollWeco);
