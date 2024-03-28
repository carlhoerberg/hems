require_relative "../modbus"
require_relative "./crc16"
require "serialport"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU < Base
    def initialize
      @lock = Mutex.new
    end

    def close
      # @serial.flock(File::LOCK_UN)
      @serial.close
      @serial = nil
    end

    private

    def request(request)
      try = 0
      @lock.synchronize do
        begin
          @response = ""
          serial.write request, CRC16.crc16(request)
          unit, function = read(2).unpack("CC")
          request_unit, request_function = request[0..1].unpack("CC")
          raise ProtocolException, "Invalid unit response" if unit != request_unit
          raise ProtocolException, "Invalid function response" if function != request_function
          check_exception!(function)
          result = yield
          read(2) # crc16 bytes
          unless CRC16.valid?(@response)
            raise ProtocolException, "Invalid CRC16"
          end
          result
        rescue ProtocolException => ex
          close
          retry if (try += 1) < 3
          raise ex
        end
      end
    end

    def read(count)
      bytes = @serial.read(count) || raise(EOFError.new)
      @response += bytes
      bytes
    end

    def serial
      # @serial ||= File.open("/dev/ttyACM0", "r+").tap do |s|
      #  s.flock(File::LOCK_EX | File::LOCK_NB) ||
      #    raise("Serial device is locked by another application")
      #  system "stty -F /dev/ttyACM0 9600 clocal cread cs8 -cstopb -parenb" ||
      #    raise("Could not set serial params")
      #  #s.timeout = 1
      # end
      @serial ||=
        begin
          device = Dir.glob("/dev/ttyACM?").first || raise("No serial device found")
          SerialPort.new(device, baud: 9600, data_bits: 8, stop_bits: 1, parity: SerialPort::NONE).tap do |s|
            s.read_timeout = 1000
          end
        end
    end
  end
end
