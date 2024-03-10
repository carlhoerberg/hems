require "socket"
require_relative "../modbus"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  # https://modbus.org/docs/Modbus_Messaging_Implementation_Guide_V1_0b.pdf
  class TCP < Base
    def initialize(host, port = 502)
      @host = host
      @port = port
    end

    def close
      @socket&.close
      @socket = nil
    end

    private

    Protocol = 0

    def request(request, &)
      try = 0
      transaction = rand(2**16)
      length = request.bytesize
      begin
        socket.write [transaction, Protocol, length, request].pack("nnna*")
        header = read(8)
        rtransaction, rprotocol, _response_length, _unit, function = header.unpack("nnnCC")
        raise "Invalid transaction (#{rtransaction} != #{transaction})" if rtransaction != transaction
        raise "Invalid protocol (#{rprotocol})" if rprotocol != Protocol
        handle_exception if function[7] == 1 # highest bit set indicates an exception
        yield
      rescue SocketError, SystemCallError => ex
        close
        retry if (try += 1) < 2
        raise ex
      end
    end

    def read(count)
      @socket.read(count)
    end

    def socket
      @socket ||= Socket.tcp(@host, @port)
    end
  end
end
