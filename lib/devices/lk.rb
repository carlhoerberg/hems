require_relative "../modbus/tcp"

class Devices
  class LK
    using Modbus::TypeExtensions

    def initialize(host, port = 502, zone_names: {}, actuator_names: {})
      @modbus = Modbus::TCP.new(host, port, timeout: 30).unit(1)
      @zone_names = zone_names
      @actuator_names = actuator_names
    end

    def actuators
      max = @actuator_names.keys.max
      statuses = @modbus.read_input_registers(60, max)
      @actuator_names.map do |i, name|
        { actuator: i, name: name, status: statuses[i - 1] }
      end
    end

    def zones
      @zone_names.map do |i, name|
        base = i * 100
        value = @modbus.read_input_register(base)
        next if value == 0
        { zone: i, name: name, actual_temperature: to_signed(value) / 10.0 }
      rescue Modbus::Base::ResponseError
        nil
      end.compact
    end

    private

    def to_signed(value)
      value > 32767 ? value - 65536 : value
    end
  end
end
