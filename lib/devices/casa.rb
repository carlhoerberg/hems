require_relative "../modbus/tcp"

class Devices
  class Casa
    def initialize(host = "192.168.0.5", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def temperature_setpoint
      read("4x5101")
    end

    def temperature_setpoint=(value)
      write("4x5101", value)
    end

    def temperatures
      v = @modbus.read_input_registers(6200, 6)
      {
        fresh: v[0] / 10.0,
        supply_before_reheater: v[1] / 10.0,
        supply: v[2] / 10.0,
        extract: v[3] / 10.0,
        exhaust: v[4] / 10.0,
        room: v[5] / 10.0,
      }
    end

    def relative_humidity
      read "3x6214"
    end

    def absolute_humidity
      read("3x6215") / 10.0
    end

    def absolute_humidity_setpoint
      read("3x6216") / 10.0
    end

    def humidity
      v = @modbus.read_input_registers(6213, 3)
      {
        relative: v[0],
        absolute: v[1] / 10.0,
        absolute_setpoint: v[2] / 10.0
      }
    end

    def measurements
      v = @modbus.read_input_registers(6200, 21)
      {
        fresh_air_temperature: v[0] / 10.0,
        supply_air_before_heater_temperature: v[1] / 10.0,
        supply_air_temperature: v[2] / 10.0,
        extract_air_temperature: v[3] / 10.0,
        exhaust_air_temperature: v[4] / 10.0,
        room_air_temperature: v[5] / 10.0,
        user_panel_1_air_temperature: v[6] / 10.0,
        user_panel_2_air_temperature: v[7] / 10.0,
        water_radiator_temperature: v[8] / 10.0,
        preheater_temperature: v[9] / 10.0,
        external_fresh_air_temperature: v[10] / 10.0,
        co2_unfiltered: v[11],
        co2_filtered: v[12],
        relative_humidity: v[13],
        absolute_humidity: v[14] / 10.0,
        absolute_humidity_setpoint: v[15] / 10.0,
        voc: v[16],
        supply_duct_pressure: v[17],
        exhaust_duct_pressure: v[18],
        supply_air_flow: v[19],
        exhaust_air_flow: v[20],
      }
    end

    def supply_control_power_output
      read "3x6317"
    end

    def supply_fan_control
      read "3x6303"
    end

    def exhaust_fan_control
      read "3x6304"
    end

    def active_alarms
      read "3x6136"
    end

    def info_alarms
      read "3x6137"
    end

    def reset_info_alarms
      write "4x5406", 1
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

    def operating_mode=(value)
      write "4x5001", value
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
  end
end
