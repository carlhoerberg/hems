require "uart"

class Devices
  class Weco
    def initialize
      device = Dir.glob("/dev/ttyUSB0").first || raise("No serial device found")
      @serial = UART.open(device, 115200)
    end

    def any
      @serial.write "\x01\x03\x00\x01\x00\x26\x1c\x2a"
      response
      @serial.write "\x01\x03\x00\x27\x00\x06\x1c\x38"
      response
      @serial.write "\x01\x03\x00\x2e\x00\x03\x1c\x38"
      response
      @serial.write "\x01\x03\x00\x52\x00\x07\x1c\x22"
      response
      @serial.write "\x01\x03\x00\x79\x00\x0a\x1c\x6a"
      response
      @serial.write "\x01\x03\x00\x8d\x00\x0a\x1c\x18"
      response
    end

    def response
      _unit, _function, len = @serial.read(3).unpack("CCC")
      p @serial.read(len).unpack("n*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
    end
  end
end
