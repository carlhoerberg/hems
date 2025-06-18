require_relative "../modbus/tcp"

class Devices
  class Casa
    def initialize(host = "192.168.0.5", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def temperature_setpoint
      read("4x5406")
    end

    def fresh_air_temperature
      read("3x6201") / 10.0
    end

    def supply_air_temperature
      read("3x6203") / 10.0
    end

    def extract_air_temperature
      read("3x6204") / 10.0
    end

    def temperatures
      values = @modbus.read_input_registers(6200, 3)
      {
        fresh: values[0] / 10.0,
        supply: values[1] / 10.0,
        extract: values[2] / 10.0
      }
    end

    def co2_ppm
      read("3x6213") / 10.0
    end

    def rh
      read "3x6214"
    end

    def voc_ppm
      read "3x6217"
    end

    def supply_fan_rpm
      read "3x6205"
    end

    def extract_fan_rpm
      read "3x6206"
    end

    def fan_rpms
      v = @modbus.read_input_registers(6204, 2)
      {
        supply: v[0],
        extract: v[1]
      }
    end

    # 0 = Ext. stop
    # 1 = User stop
    # 2 = Start
    # 3 = Normal
    # 4 = Commissioning
    def unit_state
      read "3x6301"
    end

    # 0 = Stop
    # 1 = Away
    # 2 = Home
    # 3 = Boost
    # 4 = Travelling
    def operating_mode
      read "3x6302"
    end

    # 3x6136 Combined alarm See full list
    # 3x6137 Combined info See full list

    # Read addresses as definied in the docs
    # Example: 3x072 which where 3 means read input register, and the register to read is 72 - 1
    def read(addr)
      reg = addr[2..].to_i - 1
      case addr[0]
      when "0" then @modbus.read_coil(reg)
      when "1" then @modbus.read_discrete_input(reg)
      when "3" then @modbus.read_input_register(reg)
      when "4" then @modbus.read_holding_register(reg)
      end
    end

    def write(addr, value)
      reg = addr[2..].to_i - 1
      case addr[0]
      when "0" then @modbus.write_coil(reg, value)
      when "1" then @modbus.write_discrete_input(reg, value)
      when "3" then @modbus.write_input_register(reg, value)
      when "4" then @modbus.write_holding_register(reg, value)
      end
    end

    def alarms
      alarms = @modbus.read_discrete_inputs(0, 4)
      {
        danger: alarms[0],
        high: alarms[1],
        low: alarms[2],
        warning: alarms[3]
      }
    end
  end
end
