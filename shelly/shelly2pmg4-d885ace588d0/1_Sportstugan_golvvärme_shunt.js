// Shelly 2PM Gen4 — Sportstugan floor heating shunt
//
// Regulates the mixing shunt (a 3-point actuator driven as a cover) so that the
// secondary supply temperature follows an outdoor-compensated heating curve.
//
// Sensors on the addon:
//   temperature:100 — secondary supply (out to the floor heating loops)
//   temperature:101 — secondary return (back from the loops)
//   temperature:102 — primary supply (from the culvert/boiler)
// Outdoor temperature comes from the ETA boiler, via the HEMS endpoint.
//
// The actuator has no position feedback, so the position is estimated: the cover
// is driven to a fully closed position at startup and every move is timed.

// --- Heating curve ---
const ROOM_TARGET = 20.0 // room temperature the curve is designed for (°C)
const CURVE_SLOPE = 0.4 // supply temperature rise per °C below ROOM_TARGET
const MIN_SUPPLY = 20.0 // lowest useful supply temperature (°C)
const MAX_SUPPLY = 35.0 // never send warmer water into the floor than this (°C)
const HEAT_OFF_OUTDOOR = 15.0 // above this outdoor temperature the shunt stays closed (°C)

// --- Shunt regulation ---
const Kp = 0.15 // proportional gain on the supply error, in fraction per °C
const FULL_TRAVEL_TIME = 120 // s for the actuator to go from fully closed to fully open
const DEAD_BAND = 2 // don't bother moving for smaller position changes than this (%)
const REGULATE_INTERVAL = 30000 // ms between regulation cycles

const OUTDOOR_TEMP_URL = 'http://192.168.0.2:8000/eta/outdoor_temp'

// Estimated shunt position, 0% = fully closed (all return water), 100% = fully open (all primary water)
let shuntPos = 0
let outdoorTemp = null // last known outdoor temperature (°C)

function fetchOutdoorTemperature (callback) {
  Shelly.call('HTTP.GET', { url: OUTDOOR_TEMP_URL, timeout: 10 }, function (res, error_code, error_message) {
    if (error_code !== 0 || !res || res.code !== 200) {
      print('Error fetching outdoor temperature: ' + (error_message || (res && res.code)))
      callback(outdoorTemp) // fall back to the last known value, null on the first cycle
      return;
    }
    let t = null
    try {
      t = JSON.parse(res.body) // the endpoint returns a bare number
    } catch (e) {
      print('Error parsing outdoor temperature: ' + e)
    }
    if (typeof t !== 'number') {
      print('Unexpected outdoor temperature response: ' + res.body)
      callback(outdoorTemp)
      return;
    }
    outdoorTemp = t
    callback(t)
  })
}

// Outdoor compensated supply temperature setpoint, null when no heat is needed
function supplySetpoint (T_outdoor) {
  if (T_outdoor >= HEAT_OFF_OUTDOOR) return null
  const T_set = ROOM_TARGET + CURVE_SLOPE * (ROOM_TARGET - T_outdoor)
  return Math.max(MIN_SUPPLY, Math.min(MAX_SUPPLY, T_set))
}

function getSupplyTemperature () {
  return Shelly.getComponentStatus('temperature:100').tC
}

function getReturnTemperature () {
  return Shelly.getComponentStatus('temperature:101').tC
}

function getPrimaryTemperature () {
  return Shelly.getComponentStatus('temperature:102').tC
}

function isMoving () {
  const state = Shelly.getComponentStatus('cover:0').state
  return state === 'opening' || state === 'closing'
}

function move (command, duration, newPos) {
  const params = { id: 0 }
  if (duration !== null) params.duration = duration
  Shelly.call(command, params, function (res, error_code, error_message) {
    if (error_code !== 0) {
      print('Error issuing ' + command + ': ' + error_message)
      return;
    }
    shuntPos = newPos
  })
}

function regulate () {
  if (isMoving()) {
    print('Shunt is moving, skipping regulation cycle')
    return;
  }

  fetchOutdoorTemperature(function (T_outdoor) {
    if (T_outdoor === null) {
      print('No outdoor temperature available yet, leaving shunt at ' + shuntPos + '%')
      return;
    }

    const T_setpoint = supplySetpoint(T_outdoor)
    const T_supply = getSupplyTemperature()
    const T_return = getReturnTemperature()
    const T_primary = getPrimaryTemperature()

    if (T_setpoint === null) {
      if (shuntPos !== 0) {
        print('Outdoor ' + T_outdoor + '°C, no heat needed, closing shunt')
        move('Cover.Close', null, 0)
      }
      return;
    }

    // Feed forward: the mixing ratio that would give the setpoint right now,
    // T_setpoint = T_return + x * (T_primary - T_return)
    let fraction
    if (T_primary - T_return < 0.5) {
      fraction = 1 // no primary heat available, open up and wait for it
    } else if (T_setpoint >= T_primary) {
      fraction = 1
    } else if (T_setpoint <= T_return) {
      fraction = 0
    } else {
      fraction = (T_setpoint - T_return) / (T_primary - T_return)
    }

    // Feedback: proportional correction on the measured supply error
    const error = T_setpoint - T_supply
    fraction = Math.max(0, Math.min(1, fraction + Kp * error))

    const desiredPos = Math.round(fraction * 100)
    print('Outdoor: ' + T_outdoor + '°C, setpoint: ' + T_setpoint.toFixed(1) + '°C, supply: ' + T_supply +
      '°C, return: ' + T_return + '°C, primary: ' + T_primary + '°C, position: ' + shuntPos + '% -> ' + desiredPos + '%')

    if (desiredPos === 100 && shuntPos !== 100) {
      move('Cover.Open', null, 100)
      return;
    }
    if (desiredPos === 0 && shuntPos !== 0) {
      move('Cover.Close', null, 0)
      return;
    }

    const diff = desiredPos - shuntPos
    if (Math.abs(diff) <= DEAD_BAND) return;

    const duration = Math.abs(diff) / 100 * FULL_TRAVEL_TIME
    move(diff > 0 ? 'Cover.Open' : 'Cover.Close', duration, desiredPos)
  })
}

// The actuator position is unknown at startup, so drive it fully closed to calibrate
function calibrate () {
  const state = Shelly.getComponentStatus('cover:0').state
  if (state === 'closed') {
    shuntPos = 0
    print('Shunt already closed')
  } else if (state === 'open') {
    shuntPos = 100
    print('Shunt already open')
  } else {
    print('Shunt position unknown, closing it to calibrate')
    move('Cover.Close', null, 0)
  }
}

calibrate()
Timer.set(REGULATE_INTERVAL, true, regulate)
print('Sportstugan floor heating shunt regulation started')
