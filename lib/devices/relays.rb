require_relative "../modbus/tcp"

module Devices
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
  end
end
