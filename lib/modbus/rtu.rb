require_relative "../modbus"
require_relative "./crc16"
require "uart"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  class RTU < Base
    @@lock = Mutex.new

    def close
      @@serial&.close
      @@serial = nil
    end

    private

    def request(request)
      try = 0
      @@lock.synchronize do
        @response = ""
        serial.write request, CRC16.crc16(request)
        unit, function = read(2).unpack("CC")
        request_unit, request_function = request[0..1].unpack("CC")
        raise ProtocolException, "Invalid unit response" if unit != request_unit
        raise ProtocolException, "Invalid function response" if function != request_function
        check_exception!(function)
        result = yield
        checksum = @@serial.readpartial(2) # crc16 bytes
        warn "Invalid CRC16" if checksum != CRC16.crc16(@response)
        result
      rescue ProtocolException, EOFError => e
        close
        retry if (try += 1) < 1
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
          device = Dir.glob("/dev/ttyACM?").first || raise("No serial device found")
          UART.open(device)
        end
    end
  end
end
