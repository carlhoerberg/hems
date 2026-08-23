# Hållfjället energy managment system

Hållfjället is an offgrid mountain lodge. This application automates the energy system, connecting the solar panels, batteries, diesel generator, ventilation, pellets boiler etc. Some devices are controller over Modbus, others by relays.

Main application at: [lib/energy_management.rb](lib/energy_management.rb)

## Devices

* [Studer Next3](lib/devices/next3.rb) — inverter/power management, Modbus TCP
* [Victron MultiPlus II](lib/devices/victron.rb) — inverter/charger/battery, Modbus TCP
* [Atlas Copco generator](lib/devices/gencomm.rb) — Deep Sea Electronics genset controller, Modbus TCP
* [SDMO Generator](lib/devices/sdmo.rb) — generator with Nexys controller, Modbus RTU
* [Shelly](lib/devices/shelly.rb) — smart switches/relays, HTTP/JSON
* [go-e Charger](lib/devices/goe.rb) — EV charging station, Modbus TCP
* [ETA wood pellets boiler](lib/devices/eta.rb) — wood pellets boiler, HTTP/XML
* [Weco battery BMS](lib/devices/weco.rb) — battery management system, UART/Serial
* [Grundfos Magna3](lib/devices/grundfos.rb) — circulation pump, Modbus TCP
* [Topas](lib/devices/topas.rb) — sewage treatment plant, Modbus TCP
* [LK](lib/devices/lk.rb) — heating/zone control system, Modbus TCP
* [Casa ventilation](lib/devices/casa.rb) — heating/ventilation system, Modbus TCP
* [Envistar ventilation](lib/devices/envistar.rb) — ventilation/HVAC system, Modbus TCP
* [Starlink](lib/devices/starlink.rb) — satellite internet, gRPC/HTTP
* [UniFi network](lib/devices/unifi.rb) — networking/WiFi, HTTPS/JSON
* [Ecowitt weather station](lib/devices/ecowitt.rb) — weather station, Modbus RTU
* [Östberg HERU](lib/devices/heru.rb) — FTX ventilation, Modbus TCP (9600 baud through a Waveshare RS485 gateway)
* [Wallas 40 EA](lib/devices/wallas.rb) — cabin diesel heater, BLE through [bin/wallas_agent](bin/wallas_agent), cloud HTTPS as fallback (see below)

## Wallas 40 EA cabin heater, over Bluetooth

The heater is controlled by a 3008 Advanced Control Panel at 192.168.0.90 and
there is no way in over IP. Every one of the top 1000 TCP ports on it is
filtered, its WiFi is only an uplink, and impersonating that uplink does not
work either: redirected to a local server (DNAT on the gateway for
185.87.110.36:443) the panel connects with SNI iotwallas.net and then rejects a
self signed certificate with a TLS access_denied alert. It validates the server
certificate and we cannot get a real certificate for a domain we do not own.

What does work is the Bluetooth link the phone app uses.
[bin/wallas_agent](bin/wallas_agent) runs on a Pi at 192.168.0.110, in radio
range of the panel (BLE reaches maybe 5 m, so it has to be the same room), holds
the bonded connection and serves the panel's own fields as JSON.
[lib/devices/wallas.rb](lib/devices/wallas.rb) reads it, and that is the only
source: the cloud API behind the "Wallas Remote" link works but needs internet
and is minutes behind, so it is not used.

Pair once by hand, the panel shows a six digit code that has to be typed within
about half a minute:

    bluetoothctl
    agent KeyboardOnly
    default-agent
    scan on
    pair 3C:E9:0E:96:69:3E     # code appears on the panel display
    trust 3C:E9:0E:96:69:3E

The keys land in /var/lib/bluetooth, after which the agent reconnects on its own.
Reads and notifications need that bond, service discovery does not.

Then install it as a service on that Pi with
[wallas-agent.service](wallas-agent.service), which needs `python3-dbus` and
`python3-gi`:

    sudo install -m 755 bin/wallas_agent /usr/local/bin/wallas_agent
    sudo install -m 644 wallas-agent.service /etc/systemd/system/
    sudo systemctl enable --now wallas-agent

It runs as a normal user (org.bluez lets the desktop user in) and reconnects
after a restart or a lost link on its own.

### The panel's GATT services

| Service | What it is |
| --- | --- |
| `000018b0-f642-42dd-b048-aeb8e76e93de` | WiFi provisioning: `18b1` reads the SSID, `18b2` takes the password, `18b3` notifies status |
| `00005b60-2745-479b-b006-56f3b4043c2c` | Firmware update: `5b63` reads the version, `5b64` heartbeats `00` every second |
| `c6fbdd3c-7123-4c9e-86ab-005f1a7eda01` | Live data: notify on `d769facf` and `8d4bcc34`, write on `b88e098b` and `96eb28c0` |

Telemetry is ASCII on `d769facf`, one `<field>:<value>` string per notification.
Subscribe to all five notify characteristics, the way the app does, and the panel
bursts its whole field set every 20 seconds or so; subscribe to fewer and it goes
quiet after the first burst, which cost some head scratching. Temperatures are
hundredths of a Kelvin: subtract 27315 and divide by 100.

| Field | Meaning | How it was established |
| --- | --- | --- |
| 0 | state: 0 off, 3 idle/paused | went 3 to 0 as the coolant cooled and the pumps stopped |
| 4 | room temperature | tracks the panel display |
| 5 | target room temperature | followed a 35 to 32 change made on the panel |
| 6 | coolant temperature | matches the panel display |
| 7 | target coolant temperature | 34115 = 68.00, the cloud's targetwatertemp |
| 8 | supply voltage, hundredths of a volt | 1259 = 12.59 V |
| 9 | starts | matches the cloud's starts |
| 10 | seconds counter, climbs ~1.6/s | probably uptime or total runtime |
| 15, 19 | 78.00 and 200.00, likely limits | round values that never move |
| 17, 21 | model `40EA`, panel software `1.5.14` | self evident |
| 1 | probably power percent | was 33 while circulating, 0 once fully off |
| 2 | probably the primary water pump | 1 while circulating, 0 once off |
| 3 | extra water pump | flipped to 1 the instant the app wrote `SET EWP=1` |
| 11, 12, 13, 14, 16, 18, 20 | unidentified | exported as `wallas_field{index=...}` so their meaning can be spotted from how they move |

`8d4bcc34` carries a separate `S0.A:0` string.

### Control

Commands are ASCII on `b88e098b`, and the verb matters: the notification form
`<field>:<value>` is not accepted, writes in that form are taken by the ATT layer
and ignored by the panel. The vocabulary, read off the phone app with HCI snoop
logs (Android developer options, "Enable Bluetooth HCI snoop log", operate the
app, take a bug report, then read the ATT writes with tshark):

| Command | Meaning |
| --- | --- |
| `SET RTT=30415` | room target, hundredths of a Kelvin, here 31.00 degrees |
| `SET EWP=1` | extra water pump on, `0` off |
| `STOP` | stop the heater |

There is no handshake or authorization step: the only other writes in those
captures are `0100` to the notification descriptors. Replaying them works, both
the setpoint (verified against the panel display) and `STOP`:

    curl -X POST -d '{"target_room_temperature": 24}' http://192.168.0.110:8080/set
    curl -X POST http://192.168.0.110:8080/stop

The agent needs `--allow-write` for those, `Devices::Wallas` exposes
`target_room_temperature=`, `extra_water_pump=`, `stop`, `start` and
`command_panel` for verbs that are not mapped yet, and `/wallas` is a control
page with the current values, the setpoint, the extra water pump and start/stop.
Start there needs a confirmation box ticked, since it runs a glow plug and a five
minute ignition.

`START` is assumed rather than captured: neither snoop log contains a start, so
`start` and `power = true` write a verb we have not seen the app use. The panel
ignores commands it does not recognise, which is how the wrong write format was
spotted in the first place, so the likely failure is that nothing happens. A
snoop log of pressing start in the app would settle it.
