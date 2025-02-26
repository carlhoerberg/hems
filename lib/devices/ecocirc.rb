require_relative "../modbus/tcp"

class Devices
  class EcoCirc
    def initialize(host = "192.168.40.20", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def operating_mode=(value)
      raise ArgumentError, "Operating mode must be 0 or 1" unless (0..1).include? value
      @modbus.write_holding_register(0x00, value)
    end

    def control_mode=(value)
      raise ArgumentError, "Control mode must be 1, 2 or 3" unless (1..3).include? value
      @modbus.write_holding_register(0x01, value)
    end

    def night_mode=(value)
      raise ArgumentError, "Night mode must be 0 or 1" unless (0..1).include? value
      @modbus.write_holding_register(0x02, value)
    end

    def status
      values = @modbus.read_holding_registers(0x00, 8)
      {
        operating_mode: values[0], # off/on
        control_mode: values[1], # 1: constant pressure 2: proportional pressure 3: constant curve
        night_mode: values[2], # off/on
        air_venting_procedure: values[3],
        proportional_pressure_setpoint: values[4] / 100.0, # meters
        constant_pressure_setpoint: values[5] / 100.0, # meters
        constant_curve_setpoint: values[6], # rpm
        air_venting_power_on: values[7],
      }
    end

    def measurements
      values = @modbus.read_holding_registers(0x0200, 0x10)
      {
        power: values[0], # watt
        head: values[1] / 100.0, # meters
        flow: values[2] / 10.0, # liters/second
        speed: values[3], # rpm
        temperature: values[4] / 10.0, # celsius
        external_temperature: values[5] / 10.0,
        winding_1_temperature: values[6],
        winding_2_temperature: values[7],
        winding_3_temperature: values[8],
        module_temperature: values[9],
        quadrant_current: values[10] / 100.0, # ampere
        status_io: values[11], # bit field
        alarms1: values[12], # bit field
        alarms2: values[13], # bit field
        errors: values[14], # bit field
        error_code: values[15],
      }
    end
  end
end
