require_relative "../modbus/tcp"

class Devices
  class UPS
    using Modbus::TypeExtensions

    def initialize(host = "192.168.0.13", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def status
      @modbus.read_holding_registers(0, 2).to_u32
    end

    def status_change_cause
      @modbus.read_holding_register(2)
    end

    def soc
      (@modbus.read_holding_register(130) / 2.0**9).round(1)
    end

    def battery_voltage
      (@modbus.read_holding_register(131) / 32.0).round(2)
    end

    def temperature
      (@modbus.read_holding_registers(135, 1).to_i16 / 2.0**7).round(1)
    end

    def active_power
      pct = @modbus.read_holding_register(136) / 256.0 / 100.0
      rated = 500 # @modbus.read_holding_register(589)
      (pct * rated).round(1)
    end

    def apparent_power
      pct = @modbus.read_holding_register(138) / 256.0 / 100.0
      rated = 750 # @modbus.read_holding_register(588)
      (pct * rated).round(1)
    end

    def output_current
      (@modbus.read_holding_register(140) / 2.0**5).round(2)
    end

    def output_voltage
      (@modbus.read_holding_register(142) / 2.0**6).round(2)
    end

    def frequency
      (@modbus.read_holding_register(144) / 2.0**7).round(2)
    end

    def consumed_watt_hours
      @modbus.read_holding_registers(145, 2).to_u32
    end

    def input_voltage
      (@modbus.read_holding_register(151) / 2.0**6).round(2)
    end

    def efficiency
      val = @modbus.read_holding_registers(154, 1).to_i16
      if val.negative? # enum values
        val
      else
        (val / 128.0).round(2)
      end
    end

    def runtime_remaining
      @modbus.read_holding_registers(128, 2).to_i32
    end
  end
end
