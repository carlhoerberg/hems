// Shelly i4 Dimming Control Script
// Short press = toggle lights, Hold = dim while pressed, Double press = 100%, Triple press = 60%

const CONFIG = {
  triple_press_brightness: 60, // Brightness level for triple press
  long_press_brightness: 10, // Brightness level for long press
  buttons: {
    0: { // Left button for sauna lights
      dimmers: [
        { ip: 'shellyprodm2pm-2cbcbba54cf0', id: 0 }, // Sauna lights east
        { ip: 'shellyprodm2pm-2cbcbba54cf0', id: 1 }, // Sauna lights west
        { ip: 'shellyprodm2pm-2cbcbba53e48', id: 1 }  // Sauna wall lights
      ]
    },
    1: { // Right button for hallway/shower lights
      dimmers: [
        { ip: 'shellyprodm2pm-2cbcbba53e1c', id: 0 }, // Spots in hallway
        { ip: 'shellyprodm2pm-2cbcbba53e1c', id: 1 }, // Mirror lights
        { ip: 'shellyprodm2pm-2cbcbba53e48', id: 0 }  // Spots in showers
      ]
    }
  }
}

const dimming_state = {
  0: { dim_direction: 1, is_dimming: false }, // Button 1
  1: { dim_direction: 1, is_dimming: false } // Button 2
}


// Start dimming up or down for all dimmers
function startDimming (button_id) {
  const dimmers = CONFIG.buttons[button_id].dimmers
  const direction = dimming_state[button_id].dim_direction > 0 ? 'DimUp' : 'DimDown'

  function callNext(index) {
    if (index >= dimmers.length) return;

    Shelly.call('HTTP.GET', {
      url: 'http://' + dimmers[index].ip + '/rpc/Light.' + direction + '?id=' + dimmers[index].id
    }, function() {
      callNext(index + 1)
    })
  }

  callNext(0)

  // Toggle direction for next time
  dimming_state[button_id].dim_direction *= -1
  dimming_state[button_id].is_dimming = true
}

function stopDimming (button_id) {
  if (!dimming_state[button_id].is_dimming) return;
  const dimmers = CONFIG.buttons[button_id].dimmers

  function callNext(index) {
    if (index >= dimmers.length) return;

    Shelly.call('HTTP.GET', {
      url: 'http://' + dimmers[index].ip + '/rpc/Light.DimStop?id=' + dimmers[index].id
    }, function() {
      callNext(index + 1)
    })
  }

  callNext(0)
  dimming_state[button_id].is_dimming = false
}

function toggleDimmers (button_id) {
  const dimmers = CONFIG.buttons[button_id].dimmers

  function callNext(index) {
    if (index >= dimmers.length) return;

    Shelly.call('HTTP.GET', {
      url: 'http://' + dimmers[index].ip + '/rpc/Light.Toggle?id=' + dimmers[index].id
    }, function() {
      callNext(index + 1)
    })
  }

  callNext(0)
}

function dimDimmers (button_id, brightness) {
  const dimmers = CONFIG.buttons[button_id].dimmers

  function callNext(index) {
    if (index >= dimmers.length) return;

    Shelly.call('HTTP.GET', {
      url: 'http://' + dimmers[index].ip + '/rpc/Light.Set?id=' + dimmers[index].id + '&on=true&brightness=' + brightness
    }, function() {
      callNext(index + 1)
    })
  }

  callNext(0)
}

// Button event handler
Shelly.addEventHandler(function (event) {
  // Extract button ID from component name (e.g., "input:0" -> 0)
  if (event.component && event.component.indexOf('input:') === 0) {
    const button_id = parseInt(event.component.split(':')[1])

    // Check if this button is configured
    if (!CONFIG.buttons[button_id]) return;

    if (event.info.event === 'single_push') {
      // Short press - toggle lights
      toggleDimmers(button_id)
    } else if (event.info.event === 'btn_up') {
      // Button released - stop dimming
      stopDimming(button_id)
    } else if (event.info.event === 'double_push') {
      // Double press - 100% brightness
      dimDimmers(button_id, 100)
    } else if (event.info.event === 'triple_push') {
      // Triple press - configurable brightness
      dimDimmers(button_id, CONFIG.triple_press_brightness)
    } else if (event.info.event === 'long_push') {
      // Button pressed down - start dimming
      startDimming(button_id)
    }
  }
})

// Motion sensor status handler
Shelly.addStatusHandler(function (ev, _ud) {
  // Handle bthomesensor:200 motion events
  if (ev && ev.component === "bthomesensor:200") {
    if (ev.delta && typeof ev.delta.value === "boolean") {
      if (ev.delta.value) {
        // Motion detected - same action as single push on button 1
        toggleDimmers(1);
      }
    }
  }
});

console.log("Sauna control started. Listening for button presses and bthomesensor:200 motion events");
