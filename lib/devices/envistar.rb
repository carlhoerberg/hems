require_relative "../modbus/tcp"

class Devices
  class Envistar
    using Modbus::TypeExtensions

    def initialize(host = "192.168.0.157", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    # Read addresses as definied in the docs
    # Example: 3x072 which where 3 means read input register, and the register to read is 72 - 1
    def read(addr)
      reg = addr[2..].to_i - 1
      case addr[0]
      when "0" then @modbus.read_coil(reg)
      when "1" then @modbus.read_discrete_input(reg)
      when "3" then @modbus.read_input_registers(reg, 1).to_i16
      when "4" then @modbus.read_holding_registers(reg, 1).to_i16
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

    def current_operating_mode
      read("3x0018")
    end

    def operating_mode
      read("4x0005")
    end

    # 0 = Auto
    # 1 = Off
    # 2 = Stage 1
    # 3 = Stage 2
    # 4 = Stage 3
    def operating_mode=(mode)
      write("4x0005", mode)
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

    def measurements
      {
        uteluft_temperature: read("3x072") / 10.0,
        tilluft_vvx_temperature: read("3x078") / 10.0,
        frysvakt_temperature: read("3x074") / 10.0,
        tilluft_temperature: read("3x073") / 10.0,
        franluft_temperature: read("3x076") / 10.0,
        avluft_temperature: read("3x077") / 10.0,
        tilluft_flow: read("3x095"),
        franluft_flow: read("3x096"),
        tilluft_bor_flow: read("3x400") / 100.0,
        franluft_bor_flow: read("3x402") / 100.0,
        tilluftstryck_pressure: read("3x097"),
        franluftstryck_pressure: read("3x098"),
        tilluftsfilter_pressure: read("3x148") / 10.0,
        franluftsfilter_pressure: read("3x149") / 10.0,
        tilluftsflakt_fanspeed: read("3x029"),
        franluftsflakt_fanspeed: read("3x031"),
        varme_valve: read("3x040")
      }
    end
  end
end
