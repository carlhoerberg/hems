require_relative "../modbus"
require_relative "./crc16"
require "serialport"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU < Base
    def initialize
      #@serial = File.open("/dev/ttyACM0", "r+")
      #@serial.flock(File::LOCK_EX | File::LOCK_NB) || raise("Serial device is locked by another application")
      @serial = SerialPort.new("/dev/ttyACM0", baud: 9600, data_bits: 8, stop_bits: 1, parity: SerialPort::NONE)
      @serial.read_timeout = 1
      @lock = Mutex.new
    end

    def close
      @serial.close
    end

    private

    def request(request)
      @lock.synchronize do
        @response = ""
        @serial.write request, CRC16.crc16(request)
        unit, function = read(2).unpack("CC")
        request_unit, request_function = request[0..1].unpack("CC")
        raise ProtocolException, "Invalid unit response" if unit != request_unit
        raise ProtocolException, "Invalid function response" if function != request_function
        check_exception!(function)
        yield
      ensure
        crc16 = @serial.read(2) || raise(EOFError.new)
        if crc16 != CRC16.crc16(@response)
          #@serial.close
          raise ProtocolException, "Invalid CRC16"
        end
      end
    end

    def read(count)
      bytes = @serial.read(count) || raise(EOFError.new)
      @response += bytes
      bytes
    end
  end
end
