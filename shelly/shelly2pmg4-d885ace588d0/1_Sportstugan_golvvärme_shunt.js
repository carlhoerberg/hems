// Shelly 2PM Gen4 — Sportstugan floor heating shunt
//
// Regulates the mixing shunt (a 3-point actuator driven as a calibrated cover)
// so that the secondary supply temperature follows an outdoor compensated
// heating curve.
//
// Sensors on the addon:
//   temperature:100 — secondary supply (out to the floor heating loops)
//   temperature:101 — secondary return (back from the loops)
//   temperature:102 — primary supply (from the culvert/boiler)
// Outdoor temperature comes from the ETA boiler, via the HEMS endpoint.

// --- Heating curve ---
const RoomTarget = Virtual.getHandle('number:200') // target room temperature (°C)
const CURVE_SLOPE = 0.4 // supply temperature rise per °C below the target room temperature
const MIN_SUPPLY = 20.0 // lowest useful supply temperature (°C)
const MAX_SUPPLY = 35.0 // never send warmer water into the floor than this (°C)
const HEAT_OFF_OUTDOOR = 15.0 // above this outdoor temperature the shunt stays closed (°C)

// --- Shunt regulation ---
// Integrating (floating) control: every cycle the valve is nudged in the direction
// that reduces the supply error, instead of being placed at an absolute position.
// Recomputing an absolute position from the mixing ratio oscillates, since the loop
// has a dead time of a minute or two and the valve authority is far from linear.
const STEP_GAIN = 1.5 // valve movement per °C of supply error, in % per cycle
const MAX_STEP = 6 // largest valve movement in one cycle (%)
const ERROR_DEAD_BAND = 0.5 // supply error small enough to leave the valve alone (°C)
const REGULATE_INTERVAL = 120000 // ms between regulation cycles, longer than the loop's dead time
const SAMPLE_INTERVAL = 10000 // ms between supply temperature samples
const SAMPLE_WEIGHT = 0.15 // weight of a new sample in the filtered supply temperature

const OUTDOOR_TEMP_URL = 'http://192.168.0.2:8000/eta/outdoor_temp'

let outdoorTemp = null // last known outdoor temperature (°C)
let filteredSupply = null // filtered supply temperature (°C)

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
  const T_room = RoomTarget.getValue()
  const T_set = T_room + CURVE_SLOPE * (T_room - T_outdoor)
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

// The supply temperature swings a couple of °C between readings, so regulate on a
// filtered value instead of chasing single readings around with the valve
function sampleSupplyTemperature () {
  const t = getSupplyTemperature()
  filteredSupply = filteredSupply === null ? t : filteredSupply + SAMPLE_WEIGHT * (t - filteredSupply)
}

// 0% = fully closed (all return water), 100% = fully open (all primary water)
function goToPosition (pos) {
  Shelly.call('Cover.GoToPosition', { id: 0, pos: pos }, function (res, error_code, error_message) {
    if (error_code !== 0) print('Error issuing Cover.GoToPosition: ' + error_message)
  })
}

function regulate () {
  const cover = Shelly.getComponentStatus('cover:0')
  if (cover.state === 'opening' || cover.state === 'closing') {
    print('Shunt is moving, skipping regulation cycle')
    return;
  }
  if (cover.current_pos === null) {
    print('Shunt position unknown, the cover needs to be calibrated')
    return;
  }

  fetchOutdoorTemperature(function (T_outdoor) {
    if (T_outdoor === null) {
      print('No outdoor temperature available yet, leaving shunt at ' + cover.current_pos + '%')
      return;
    }

    const T_setpoint = supplySetpoint(T_outdoor)
    const T_supply = filteredSupply
    const T_return = getReturnTemperature()
    const T_primary = getPrimaryTemperature()

    if (T_setpoint === null) {
      if (cover.current_pos !== 0) {
        print('Outdoor ' + T_outdoor + '°C, no heat needed, closing shunt')
        goToPosition(0)
      }
      return;
    }

    const error = T_setpoint - T_supply
    let step = STEP_GAIN * error
    step = Math.max(-MAX_STEP, Math.min(MAX_STEP, step))
    const desiredPos = Math.max(0, Math.min(100, Math.round(cover.current_pos + step)))

    print('Outdoor: ' + T_outdoor + '°C, room target: ' + RoomTarget.getValue() + '°C, setpoint: ' + T_setpoint.toFixed(1) + '°C, supply: ' + T_supply.toFixed(1) +
      '°C, return: ' + T_return + '°C, primary: ' + T_primary + '°C, position: ' + cover.current_pos + '% -> ' + desiredPos + '%')

    if (Math.abs(error) <= ERROR_DEAD_BAND) return;
    if (desiredPos !== cover.current_pos) goToPosition(desiredPos)
  })
}

sampleSupplyTemperature()
Timer.set(SAMPLE_INTERVAL, true, sampleSupplyTemperature)
Timer.set(REGULATE_INTERVAL, true, regulate)
regulate()
print('Sportstugan floor heating shunt regulation started')
