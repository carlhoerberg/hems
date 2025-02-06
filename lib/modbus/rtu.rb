require_relative "../modbus"
require_relative "./crc16"
require "uart"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU < Base
    @@lock = Mutex.new

    def initialize(device = "/dev/ttyACM?", baud_rate = 9600)
      @device = device
      @baud_rate = baud_rate
    end

    def close
      @@serial&.close
      @@serial = nil
    end

    private

    def request(request)
      try = 0
      @@lock.synchronize do
        @response = ""
        serial.write request, CRC16.compute(request)
        unit, function = read(2).unpack("CC")
        request_unit, request_function = request[0..1].unpack("CC")
        raise ProtocolException, "Invalid unit response" if unit != request_unit && request_unit != 0
        raise ProtocolException, "Invalid function response" if function != request_function
        check_exception!(function)
        result = yield
        checksum = @@serial.readpartial(2) # crc16 bytes
        warn "Invalid CRC16" if checksum != CRC16.compute(@response)
        result
      rescue ProtocolException, IOError, SystemCallError => e
        close
        retry if (try += 1) < 2
        raise e
      end
    end

    def read(count)
      bytes = @@serial.read(count) || raise(EOFError.new)
      @response += bytes
      bytes
    end

    def serial
      @@serial ||=
        begin
          device = Dir.glob(@device).first || raise("No serial device found")
          UART.open(device, @baud_rate)
        end
    end
  end
end
