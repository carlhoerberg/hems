require "uart"

class Devices
  class Weco
    def initialize
      device = Dir.glob("/dev/ttyUSB0").first || raise("No serial device found")
      @serial = UART.open(device, 115200)
    end

    def any
      @serial.write "\x01\x03\x00\x01\x00\x26\x1c\x2a"
      p @serial.read(0x26 * 2 + 5)
      @serial.write "\x01\x03\x00\x27\x00\x06\x1c\x38"
      p @serial.read(0x06 * 2 + 5)
      @serial.write "\x01\x03\x00\x2d\x00\x01\x1c\x78"
      p @serial.read(0x01 * 2 + 5)
      @serial.write "\x01\x03\x00\x2e\x00\x03\x1c\x38"
      p @serial.read(0x03 * 2 + 5)
      @serial.write "\x01\x03\x00\x33\x00\x1d\x1c\x32"
      p @serial.read(0x1d * 2 + 5)
      @serial.write "\x01\x03\x00\x52\x00\x07\x1c\x22"
      p @serial.read(0x07 * 2 + 5)
      @serial.write "\x01\x03\x00\x5b\x00\x1e\x1c\x6a"
      p @serial.read(0x1e * 2 + 5)
      @serial.write "\x01\x03\x00\x79\x00\x0a\x1c\x6a"
      p @serial.read(0x0a * 2 + 5).unpack("CCCn*CC")
      @serial.write "\x01\x03\x00\x83\x00\x0a\x1c\x5a"
      p @serial.read(0x0a * 2 + 5).unpack("CCCn*CC")
      @serial.write "\x01\x03\x00\x8d\x00\x0a\x1c\x18"
      p @serial.read(0x0a * 2 + 5).unpack("CCCn*CC")
      @serial.write "\x01\x03\x01\xc8\x00\x0e\x1c\x72"
      p @serial.read(0x0e * 2 + 5).unpack("CCCn*CC")
    end
  end
end
