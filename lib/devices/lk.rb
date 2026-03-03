require_relative "../modbus/tcp"

class Devices
  class LK
    using Modbus::TypeExtensions

    ACTUATOR_STATUS = {
      0 => "off",
      1 => "on",
      2 => "unknown",
    }.freeze

    def initialize(host, port = 502, zone_names: {})
      @modbus = Modbus::TCP.new(host, port, timeout: 30).unit(1)
      @zone_names = zone_names
    end

    def zone_name(zone_number)
      @zone_names[zone_number] || "Zone #{zone_number}"
    end

    def actuator_name(actuator_number, zones_data)
      zones_data.each do |z|
        return z[:name] if z[:connected_actuators][actuator_number - 1] == 1
      end
      "Actuator #{actuator_number}"
    end

    def configured_zones
      @zone_names.keys
    end

    def connected_actuator_numbers(bitmask)
      (0..11).select { |bit| bitmask[bit] == 1 }.map { |bit| bit + 1 }
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

    def actuators(zones_data = nil)
      zones_data ||= zones
      statuses = actuator_statuses
      actuator_nums = zones_data.flat_map { |z| connected_actuator_numbers(z[:connected_actuators]) }.uniq.sort
      actuator_nums.map do |i|
        { actuator: i, name: actuator_name(i, zones_data), status: statuses[i - 1] }
      end
    end

    def zone(zone_number)
      raise ArgumentError, "Zone must be 1-12" unless (1..12).include?(zone_number)
      base = zone_number * 100
      input = @modbus.read_input_registers(base, 8)
      {
        actual_temperature: to_signed(input[0]) / 10.0,
        actual_humidity: input[1] / 10.0,
        battery: input[2],
        signal_strength: to_signed(input[3]),
        connected_actuators: input[7],
      }
    end

    def zones
      configured_zones.map do |i|
        zone(i).merge(zone: i, name: zone_name(i))
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
