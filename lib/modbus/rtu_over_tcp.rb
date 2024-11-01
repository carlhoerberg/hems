require_relative "./tcp"
require_relative "./crc16"

module Modbus
  class RTUoverTCP < TCP

    private

    def request(request)
      try = 0
      @lock.synchronize do
        @response = ""
        socket.write request, CRC16.crc16(request)
        unit, function = read(2).unpack("CC")
        request_unit, request_function = request[0..1].unpack("CC")
        raise ProtocolException, "Invalid unit response" if unit != request_unit
        raise ProtocolException, "Invalid function response" if function != request_function
        check_exception!(function)
        result = yield
        checksum = read(2) # crc16 bytes
        warn "Invalid CRC16" if checksum != CRC16.crc16(@response[0..-3])
        result
      rescue ProtocolException, IOError, SystemCallError => e
        close
        retry if (try += 1) < 2
        raise e
      end
    end
  end

  def read(count, timeout = 1)
    bytes = super
    @response += bytes # store full packet for CRC validation
    bytes
  end
end
