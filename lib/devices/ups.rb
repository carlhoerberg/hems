require_relative "../modbus/tcp"

class Devices
  class UPS
    using Modbus::TypeExtensions

    def initialize(host = "192.168.0.13", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def soc
      (@modbus.read_holding_register(130) / 2.0**9).round(1)
    end

    def temperature
      (@modbus.read_holding_register(135) / 2.0**7).round(1)
    end

    def output_current
      (@modbus.read_holding_register(140) / 2.0**5).round(1)
    end

    def output_voltage
      (@modbus.read_holding_register(142) / 2.0**6).round(1)
    end

    def frequency
      (@modbus.read_holding_register(144) / 2.0**7).round(1)
    end

    def consumed_watt_hours
      @modbus.read_holding_registers(145, 2).to_i32
    end

    def input_voltage
      (@modbus.read_holding_register(151) / 2.0**6).round(1)
    end

    def runtime_remaining
      @modbus.read_holding_registers(128, 2).to_i32
    end
  end
end
