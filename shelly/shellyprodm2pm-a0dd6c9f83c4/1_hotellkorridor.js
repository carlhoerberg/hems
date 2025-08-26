// Shelly script for motion-triggered lighting control

let CONFIG = {
  motionDeviceMac: "b0:c7:de:40:a3:35",
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

// BLE decoding constants and functions
const BTHOME_SVC_ID_STR = "fcd2";

const uint8 = 0;
const int8 = 1;
const uint16 = 2;
const int16 = 3;
const uint24 = 4;
const int24 = 5;

const BTH = {
  0x00: { n: "pid", t: uint8 },
  0x01: { n: "battery", t: uint8, u: "%" },
  0x05: { n: "illuminance", t: uint24, f: 0.01 },
  0x21: { n: "motion", t: uint8 },
  0x3a: { n: "button", t: uint8 }
};

function getByteSize(type) {
  if (type === uint8 || type === int8) return 1;
  if (type === uint16 || type === int16) return 2;
  if (type === uint24 || type === int24) return 3;
  return 255;
}

const BTHomeDecoder = {
  utoi: function (num, bitsz) {
    const mask = 1 << (bitsz - 1);
    return num & mask ? num - (1 << bitsz) : num;
  },
  getUInt8: function (buffer) {
    return buffer.at(0);
  },
  getInt8: function (buffer) {
    return this.utoi(this.getUInt8(buffer), 8);
  },
  getUInt16LE: function (buffer) {
    return 0xffff & ((buffer.at(1) << 8) | buffer.at(0));
  },
  getInt16LE: function (buffer) {
    return this.utoi(this.getUInt16LE(buffer), 16);
  },
  getUInt24LE: function (buffer) {
    return (
      0x00ffffff & ((buffer.at(2) << 16) | (buffer.at(1) << 8) | buffer.at(0))
    );
  },
  getInt24LE: function (buffer) {
    return this.utoi(this.getUInt24LE(buffer), 24);
  },
  getBufValue: function (type, buffer) {
    if (buffer.length < getByteSize(type)) return null;
    let res = null;
    if (type === uint8) res = this.getUInt8(buffer);
    if (type === int8) res = this.getInt8(buffer);
    if (type === uint16) res = this.getUInt16LE(buffer);
    if (type === int16) res = this.getInt16LE(buffer);
    if (type === uint24) res = this.getUInt24LE(buffer);
    if (type === int24) res = this.getInt24LE(buffer);
    return res;
  },
  unpack: function (buffer) {
    if (typeof buffer !== "string" || buffer.length === 0) return null;
    let result = {};
    let _dib = buffer.at(0);
    result["encryption"] = _dib & 0x1 ? true : false;
    result["BTHome_version"] = _dib >> 5;
    if (result["BTHome_version"] !== 2) return null;
    if (result["encryption"]) return result;
    buffer = buffer.slice(1);

    let _bth;
    let _value;
    while (buffer.length > 0) {
      _bth = BTH[buffer.at(0)];
      if (typeof _bth === "undefined") {
        console.log("BTH: Unknown type");
        break;
      }
      buffer = buffer.slice(1);
      _value = this.getBufValue(_bth.t, buffer);
      if (_value === null) break;
      if (typeof _bth.f !== "undefined") _value = _value * _bth.f;

      if (typeof result[_bth.n] === "undefined") {
        result[_bth.n] = _value;
      } else {
        if (Array.isArray(result[_bth.n])) {
          result[_bth.n].push(_value);
        } else {
          result[_bth.n] = [result[_bth.n], _value];
        }
      }
      buffer = buffer.slice(getByteSize(_bth.t));
    }
    return result;
  }
};

let lastPacketId = 0x100;

function onBLEResult(ev, res) {
  if (ev !== BLE.Scanner.SCAN_RESULT) return;
  if (res.addr !== CONFIG.motionDeviceMac) return;

  if (
    typeof res.service_data === "undefined" ||
    typeof res.service_data[BTHOME_SVC_ID_STR] === "undefined"
  ) {
    return;
  }

  let unpackedData = BTHomeDecoder.unpack(res.service_data[BTHOME_SVC_ID_STR]);

  if (unpackedData["encryption"]) {
    console.log("Encrypted devices are not supported");
    return;
  }

  if (lastPacketId === unpackedData.pid) return;
  lastPacketId = unpackedData.pid;

  console.log("Hotel corridor BLE data:", JSON.stringify(unpackedData));

  if (unpackedData.motion === 1) {
    handleMotionDetected();
  } else {
    handleNoMotion();
  }
}

// Start BLE scanning
BLE.Scanner.Start({
  duration_ms: 0, // Continuous scanning
  interval_ms: 100
}, onBLEResult);
