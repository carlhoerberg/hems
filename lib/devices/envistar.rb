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
