require_relative "../modbus/tcp"

class Devices
  class LK
    using Modbus::TypeExtensions

    ACTUATOR_STATUS = {
      0 => "off",
      1 => "on",
      2 => "unknown",
    }.freeze

    def initialize(host, port = 502)
      @modbus = Modbus::TCP.new(host, port, timeout: 15).unit(1)
    end

    def number_of_zones
      @modbus.read_input_register(50)
    end

    def actuator_status(actuator)
      raise ArgumentError, "Actuator must be 1-12" unless (1..12).include?(actuator)
      @modbus.read_input_register(59 + actuator)
    end

    def actuator_statuses
      @modbus.read_input_registers(60, 12)
    end

    def zone(zone_number)
      raise ArgumentError, "Zone must be 1-12" unless (1..12).include?(zone_number)
      base = zone_number * 100
      input = @modbus.read_input_registers(base, 8)
      holding = @modbus.read_holding_registers(base, 3)
      {
        actual_temperature: to_signed(input[0]) / 10.0,
        actual_humidity: input[1] / 10.0,
        battery: input[2],
        signal_strength: to_signed(input[3]),
        connected_actuators: input[7],
        target_temperature: to_signed(holding[0]) / 10.0,
        override: holding[1] == 1,
        override_level: holding[2],
      }
    end

    def zones
      num_zones = number_of_zones
      (1..num_zones).map do |i|
        zone(i).merge(zone: i)
      rescue Modbus::Base::ResponseError
        nil
      end.compact
    end

    def set_target_temperature(zone_number, temp)
      raise ArgumentError, "Zone must be 1-12" unless (1..12).include?(zone_number)
      raise ArgumentError, "Temperature must be between -100 and 100" unless (-100..100).include?(temp)
      base = zone_number * 100
      @modbus.write_holding_register(base, (temp * 10).to_i)
    end

    private

    def to_signed(value)
      value > 32767 ? value - 65536 : value
    end
  end
end
