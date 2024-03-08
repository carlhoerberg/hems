require "serialport"
require_relative "../modbus"
require_relative "./crc16"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU
    def initialize
      @serial = SerialPort.new("/dev/ttyACM0", 9600, 8, 1, SerialPort::NONE)
      @serial.read_timeout  = 2000 # milliseconds
      @serial.write_timeout = 1000 # milliseconds
    end

    def close
      @serial.close
    end

    private

    def request(request)
      @serial.write CRC16.add_crc(request)
      @response = @serial.read(2) # unit and function
      ret = yield
      crc16 = socket.read(2)
      if crc16 != CRC16.crc16(@response) 
        @serial.close
        raise "Invalid CRC16"
      end
      ret
    end

    def read(count)
      bytes = @serial.read(count)
      @response += bytes
      bytes
    end
  end
end
