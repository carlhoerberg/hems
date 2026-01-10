require_relative "../modbus/tcp"

class Devices
  class LK
    using Modbus::TypeExtensions

    ACTUATOR_STATUS = {
      0 => "off",
      1 => "on",
      2 => "unknown",
    }.freeze

    def initialize(host, port = 502, zone_names: {}, actuator_names: {})
      @modbus = Modbus::TCP.new(host, port, timeout: 30).unit(1)
      @zone_names = zone_names
      @actuator_names = actuator_names
    end

    def zone_name(zone_number)
      @zone_names[zone_number] || "Zone #{zone_number}"
    end

    def actuator_name(actuator_number)
      @actuator_names[actuator_number] || "Actuator #{actuator_number}"
    end

    def configured_zones
      @zone_names.keys
    end

    def configured_actuators
      @actuator_names.keys
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

    def actuators
      statuses = actuator_statuses
      configured_actuators.map do |i|
        { actuator: i, name: actuator_name(i), status: statuses[i - 1] }
      end
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
      configured_zones.map do |i|
        zone(i).merge(zone: i, name: zone_name(i))
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
