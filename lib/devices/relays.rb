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

    def status
      @modbus.read_coils(0, 8)
    end

    def address
      @modbus.read_holding_register(0x4000)
    end

    def version
      @modbus.read_holding_register(0x8000)
    end

    def start_9kw_heater
      activate(0)
    end

    def stop_9kw_heater
      deactivate(0)
    end

    def start_6kw_heater
      activate(1)
    end

    def stop_6kw_heater
      deactivate(1)
    end

    def open_air_vents
      activate(3)
      activate(4)
    end

    def close_air_vents
      deactivate(3)
      deactivate(4)
    end
  end
end
