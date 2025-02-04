require_relative "../modbus/rtu"

class Devices
  class Ecowitt
    using Modbus::TypeExtensions

    def initialize
      @m = Modbus::RTU.new("/dev/ttyUSB1").unit(0x90)
    end

    def temperature
      v = @m.read_holding_register(0x0167)
      ((v - 400) / 10.0).round(1)
    end

    def measurements
      @m.read_holding_registers(0x0165, 9)
    end
  end
end
