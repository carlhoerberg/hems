require_relative "../modbus/rtu"

class Devices
  class Weco
    using Modbus::TypeExtensions

    def initialize
      @weco = Modbus::RTU.new("/dev/ttyUSB?", 115200)
    end

    def any
      @weco.serial.write "\x00\x03\x00\x00\x00\x01"
      p @weco.unit(1).read_holding_registers(1, 38)
      p @weco.unit(1).read_holding_registers(39, 6)
    end
  end
end
