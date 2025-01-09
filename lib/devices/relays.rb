require_relative "../modbus/tcp"

class Devices
  class Relays
    def initialize(host = "192.168.0.200", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def activate(id)
      @modbus.write_coil(id, true)
    end

    def deactivate(id)
      @modbus.write_coil(id, false)
    end

    def toggle(id)
      @modbus.write_coil(id, 0x5500)
    end

    def status
      @modbus.read_coils(0, 8)
    end

    def address
      @modbus.read_holding_register(0x4000)
    end

    def version
      @modbus.read_holding_register(0x8000)
    end

    def any_heater_on?
      status[0..1].any?
    end

    def heater_9kw?
      status[0]
    end

    def heater_9kw=(on_off)
      @modbus.write_coil(0, on_off)
    end

    def heater_6kw?
      status[1]
    end

    def heater_6kw=(on_off)
      @modbus.write_coil(1, on_off)
    end

    @air_vents_open = false

    def open_air_vents
      return if @air_vents_open
      activate(3)
      activate(4)
      @air_vents_open = true
    end

    def close_air_vents
      return unless @air_vents_open
      deactivate(3)
      deactivate(4)
      @air_vents_open = false
    end
  end
end
