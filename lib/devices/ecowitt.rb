require_relative "../modbus/rtu"

class Devices
  class Ecowitt
    using Modbus::TypeExtensions

    def initialize
      @m = Modbus::RTU.new("/dev/ttyUSB1").unit(0x90)
    end

    def temperature
      @m.read_input_register(0x0167)
    end
  end
end
