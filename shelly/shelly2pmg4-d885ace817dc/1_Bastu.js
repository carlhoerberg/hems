// Shelly 2PM Gen4 — Casa preheater shunt
//
// Regulates the mixing shunt of the water preheater coil in front of the Swegon
// Casa FTX unit. The goal is to recover as much heat as possible from the extract
// air and add as little as possible with the preheater: the exhaust (waste) air
// leaving the exchanger is held just above freezing, so condensation in the
// exchanger never freezes and the Casa never has to run its own defrost. If the
// exhaust air is warmer than that the shunt closes. The secondary pump stops when
// the shunt is fully closed; the circuit is glycol filled so the coil may stand still.
//
// Sensors on the addon:
//   temperature:100 — primary supply (from the boiler/culvert)
//   temperature:101 — secondary return (back from the coil)
//   temperature:102 — secondary supply (out to the preheater coil)
// bthomesensor:202 — outdoor temperature (BLE sensor)
// Exhaust air temperature is read from the Casa via the HEMS,
// Casa Smart Modbus input register 3x6205 in 0.1°C. The HEMS addresses are
// zero based, so it is read as 6204.
//
// The shunt is a 3-point actuator driven as an uncalibrated cover, so it is
// nudged with timed Cover.Open/Cover.Close calls and the position is estimated.

// --- Setpoints ---
const EXHAUST_AIR_SETPOINT = 1.5 // exhaust air temperature out of the exchanger, just above freezing (°C)
const PREHEAT_ON_OUTDOOR = 0.0 // the exchanger can only frost when outdoor is below this (°C)
const PREHEAT_OFF_OUTDOOR = 2.0 // above this the shunt is closed without regulating (°C), hysteresis

// --- Shunt regulation ---
// Integrating (floating) control: every cycle the valve is moved for a time
// proportional to the exhaust air error, instead of being placed at an absolute
// position. That way the estimated position only matters for logging and
// end-stop handling, never for the regulation itself.
const FULL_MOVEMENT_TIME = 90 // seconds for the actuator to travel closed -> open
const STEP_GAIN = 1.5 // valve movement per °C of error, in % per cycle
const MAX_STEP = 8 // largest valve movement in one cycle (%)
const MIN_STEP = 1 // smaller moves than this are skipped (%)
const ERROR_DEAD_BAND = 0.3 // exhaust air error small enough to leave the valve alone (°C)
const REGULATE_INTERVAL = 60000 // ms between regulation cycles

const EXHAUST_AIR_URL = 'http://192.168.0.8/api/read_input?start_addr=6204'

// Estimated shunt position (%), 0 = all return water, 100 = all primary water.
// Kept in a virtual component so it survives script restarts and reboots.
const ShuntPosition = Virtual.getHandle('number:200')
let position = ShuntPosition.getValue()
let preheating = false

function getPrimaryTemperature () {
  return Shelly.getComponentStatus('temperature:100').tC
}

function getSupplyTemperature () {
  return Shelly.getComponentStatus('temperature:102').tC
}

function getReturnTemperature () {
  return Shelly.getComponentStatus('temperature:101').tC
}

function getOutdoorTemperature () {
  const s = Shelly.getComponentStatus('bthomesensor:202')
  return s && typeof s.value === 'number' ? s.value : null
}

function fetchExhaustAirTemperature (callback) {
  Shelly.call('HTTP.GET', { url: EXHAUST_AIR_URL, timeout: 10 }, function (res, error_code, error_message) {
    if (error_code !== 0 || !res || res.code !== 200) {
      print('Error fetching exhaust air temperature: ' + (error_message || (res && res.code)))
      callback(null)
      return;
    }
    let t = null
    try {
      const response = JSON.parse(res.body)
      if (response.success && Array.isArray(response.data) && response.data.length > 0) {
        let raw = response.data[0]
        if (raw > 32767) raw -= 65536 // signed 16 bit register
        t = raw / 10.0
      }
    } catch (e) {
      print('Error parsing exhaust air temperature: ' + e)
    }
    if (t === null) print('Unexpected exhaust air temperature response: ' + (res.body || ''))
    callback(t)
  })
}

function isMoving () {
  const state = Shelly.getComponentStatus('cover:0').state
  return state === 'opening' || state === 'closing'
}

// Move the valve by step percentage points, positive opens (more primary water)
function move (step) {
  const command = step > 0 ? 'Cover.Open' : 'Cover.Close'
  const duration = Math.abs(step) / 100 * FULL_MOVEMENT_TIME
  const target = Math.max(0, Math.min(100, position + step))
  Shelly.call(command, { id: 0, duration: duration }, function (res, error_code, error_message) {
    if (error_code !== 0) {
      print('Error issuing ' + command + ': ' + error_message)
    } else {
      position = target
      ShuntPosition.setValue(position)
    }
  })
}

// Drive the actuator to an end stop, which also resynchronises the estimated position
function driveToEnd (open) {
  const command = open ? 'Cover.Open' : 'Cover.Close'
  Shelly.call(command, { id: 0 }, function (res, error_code, error_message) {
    if (error_code !== 0) {
      print('Error issuing ' + command + ': ' + error_message)
    } else {
      position = open ? 100 : 0
      ShuntPosition.setValue(position)
    }
  })
}

function regulate () {
  if (isMoving()) {
    print('Shunt is moving, skipping regulation cycle')
    return;
  }

  const T_outdoor = getOutdoorTemperature()
  const T_return = getReturnTemperature()
  const T_supply = getSupplyTemperature()
  const T_primary = getPrimaryTemperature()

  if (T_outdoor === null) {
    print('No outdoor temperature available, leaving shunt at ' + position + '%')
    return;
  }

  if (preheating && T_outdoor > PREHEAT_OFF_OUTDOOR) preheating = false
  if (!preheating && T_outdoor < PREHEAT_ON_OUTDOOR) preheating = true

  if (!preheating) {
    if (position !== 0) {
      print('Outdoor ' + T_outdoor + '°C, no frost risk, closing shunt')
      driveToEnd(false)
    }
    return;
  }

  fetchExhaustAirTemperature(function (T_air) {
    if (T_air === null) {
      print('No exhaust air temperature available, leaving shunt at ' + position + '%')
      return;
    }

    const error = EXHAUST_AIR_SETPOINT - T_air
    let step = STEP_GAIN * error
    step = Math.max(-MAX_STEP, Math.min(MAX_STEP, step))
    step = Math.round(step)

    print('Outdoor: ' + T_outdoor + '°C, exhaust air: ' + T_air.toFixed(1) + '°C (setpoint ' + EXHAUST_AIR_SETPOINT + '°C), primary: ' + T_primary +
      '°C, supply: ' + T_supply + '°C, return: ' + T_return + '°C, position: ' + position + '% -> ' + Math.max(0, Math.min(100, position + step)) + '%')

    if (Math.abs(error) <= ERROR_DEAD_BAND) return;
    if (Math.abs(step) < MIN_STEP) return;
    if (step > 0 && position >= 100) return;
    if (step < 0 && position <= 0) return;
    move(step)
  })
}

// Only synchronise the position estimate against an end stop when none is stored,
// the regulation opens the shunt again if needed
if (typeof position !== 'number') {
  print('No stored shunt position, closing fully to synchronise')
  driveToEnd(false)
} else {
  print('Resuming with stored shunt position ' + position + '%')
}

Timer.set(REGULATE_INTERVAL, true, regulate)
print('Casa preheater shunt regulation started')
