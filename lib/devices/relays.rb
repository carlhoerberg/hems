require_relative "../modbus/tcp"

module Devices
  class Relays
    def initialize(host, port = 502)
      @modbus = Modbus::TCP.new(host, port)
    end

    def activate(id)
      @modbus.write_coil(id, true, 1)
    end

    def deactivate(id)
      @modbus.write_coil(id, false, 1)
    end
  end
end
