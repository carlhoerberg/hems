require "serialport"
require_relative "../modbus"
require_relative "./crc16"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU < Base
    def initialize
      @serial = SerialPort.new("/dev/ttyACM0", 9600, 8, 1, SerialPort::NONE)
      @serial.read_timeout  = 2000 # milliseconds
      @lock = Mutex.new
    end

    def close
      @serial.close
    end

    private

    def request(request)
      @lock.synchronize do
        @serial.write request, CRC16.crc16(request)
        @response = ""
        _unit = read(1).unpack1("C")
        function = read(1).unpack1("C")
        handle_exception if function[7] == 1 # highest bit set indicates an exception
        yield
      ensure
        crc16 = socket.read(2)
        if crc16 != CRC16.crc16(@response)
          @serial.close
          raise "Invalid CRC16"
        end
      end
    end

    def read(count)
      bytes = @serial.read(count)
      @response += bytes
      bytes
    end
  end
end
