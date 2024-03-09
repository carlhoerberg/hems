require_relative "../modbus/tcp"

module Devices
  class Boiler
    def initialize(host, port = 502)
      @modbus = Modbus::TCP.new(host, port)
    end
  end
end
