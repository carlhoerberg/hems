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
