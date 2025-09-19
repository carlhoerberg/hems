// Shelly i4 Dimming Control Script
// Short press = toggle lights, Hold = dim while pressed, Double press = 100%, Triple press = 60%

const CONFIG = {
  triple_press_brightness: 40, // Brightness level for triple press
  buttons: {
    0: { // Button for lounge lights
      dimmers: [
        { ip: 'shellyprodm2pm-a0dd6c9e824c', id: 0 },
        { ip: 'shellyprodm2pm-a0dd6c9e824c', id: 1 },
        { ip: 'shellyprodm2pm-a0dd6c9de504', id: 0 },
        { ip: 'shellyprodm2pm-a0dd6c9de504', id: 1 },
        { ip: 'shellyprodm1pm-34987aa95f98', id: 0 },
        { ip: 'shellydimmerg3-b08184ef979c', id: 0 },
        { ip: 'shellydimmerg3-b08184ef8c18', id: 0 },
        { ip: 'shellydimmerg3-b08184f02750', id: 0 }
      ]
    },
    1: { // Button for kitchen lights
      dimmers: [
        { ip: 'shellydimmerg3-b08184f26d28', id: 0 }, // Korridor
        { ip: 'shellydimmerg3-b08184f16124', id: 0 }, // Lampetter källaren
        { ip: 'shellydimmerg3-b08184f149a4', id: 0 }, // Källarhall spot
        //{ ip: 'shellydimmerg3-b08184f29bb8', id: 0 }, // Vinkällaren
        { ip: 'shellyprodm2pm-2cbcbb9f69e4', id: 0 }, // I köksskåpen
        { ip: 'shellyprodm2pm-2cbcbb9f69e4', id: 1 }, // Under köksskåpen
        { ip: 'shellyprodm2pm-a0dd6c9e8668', id: 0 }, // Spottar kök
        { ip: 'shellyprodm2pm-a0dd6c9e8668', id: 1 }, // Spottar infälda kök
        { ip: 'shellyprodm1pm-34987aa8d98c', id: 0 }, // Köksön
        { ip: 'shellydimmerg3-b08184f15270', id: 0 }, // Spiskåpa lister
        { ip: 'shellyddimmerg3-e4b063d574bc', id: 0 }, // Spiskåpa armatur
      ]
    },
  }
}

const dimming_state = {
  0: { dim_direction: 1, is_dimming: false },
  1: { dim_direction: 1, is_dimming: false }
}

// Queue for managing HTTP requests with max 4 concurrent calls
let httpQueue = {
  head: null,
  tail: null,
  active: 0,
  maxConcurrent: 4
}

function processHttpQueue() {
  while (httpQueue.active < httpQueue.maxConcurrent && httpQueue.head) {
    const request = httpQueue.head
    httpQueue.head = request.next
    if (!httpQueue.head) httpQueue.tail = null
    httpQueue.active++

    Shelly.call('HTTP.GET', request.params, function(result, error_code, error_message) {
      httpQueue.active--
      if (request.callback) request.callback(result, error_code, error_message)
      processHttpQueue()
    })
  }
}

function queueHttpGet(params, callback) {
  const node = { params: params, callback: callback, next: null }
  if (httpQueue.tail) {
    httpQueue.tail.next = node
  } else {
    httpQueue.head = node
  }
  httpQueue.tail = node
  processHttpQueue()
}

// Start dimming up or down for all dimmers
function startDimming (button_id) {
  dimming_state[button_id].is_dimming = true

  const dimmers = CONFIG.buttons[button_id].dimmers
  const direction = dimming_state[button_id].dim_direction > 0 ? 'DimUp' : 'DimDown'
  for (let i = 0; i < dimmers.length; i++) {
    queueHttpGet({
      url: 'http://' + dimmers[i].ip + '/rpc/Light.' + direction + '?id=' + dimmers[i].id
    })
  }

  // Toggle direction for next time
  dimming_state[button_id].dim_direction *= -1
}

function stopDimming (button_id) {
  if (!dimming_state[button_id].is_dimming) return;
  const dimmers = CONFIG.buttons[button_id].dimmers
  for (let i = 0; i < dimmers.length; i++) {
    queueHttpGet({
      url: 'http://' + dimmers[i].ip + '/rpc/Light.DimStop?id=' + dimmers[i].id
    })
  }
  dimming_state[button_id].is_dimming = false
}

function toggleDimmers (button_id) {
  const dimmers = CONFIG.buttons[button_id].dimmers
  for (let i = 0; i < dimmers.length; i++) {
    queueHttpGet({
      url: 'http://' + dimmers[i].ip + '/rpc/Light.Toggle?id=' + dimmers[i].id
    })
  }
}

function dimDimmers (button_id, brightness) {
  const dimmers = CONFIG.buttons[button_id].dimmers
  for (let i = 0; i < dimmers.length; i++) {
    queueHttpGet({
      url: 'http://' + dimmers[i].ip + '/rpc/Light.Set?id=' + dimmers[i].id + '&on=true&brightness=' + brightness
    })
  }
}

let isDimming = false

// Button event handler
function onEvent (event) {
  // Extract button ID from component name (e.g., "input:0" -> 0)
  if (event.component && event.component.indexOf('input:') === 0) {
    const button_id = parseInt(event.component.split(':')[1])
    // Check if this button is configured
    if (!CONFIG.buttons[button_id]) return;

    if (event.info.event === 'single_push') {
      toggleDimmers(button_id)
    } else if (event.info.event === 'double_push') {
      dimDimmers(button_id, 100)
    } else if (event.info.event === 'triple_push') {
      dimDimmers(button_id, CONFIG.triple_press_brightness)
    } else if (event.info.event === 'long_push') {
      // Button pressed down - start dimming
      startDimming(button_id)
    } else if (event.info.event === 'btn_up') {
      // Button released - stop dimming
      stopDimming(button_id)
    }
  }
}

Shelly.addEventHandler(onEvent)
