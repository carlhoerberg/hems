require "socket"
require_relative "../modbus"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  # https://modbus.org/docs/Modbus_Messaging_Implementation_Guide_V1_0b.pdf
  class TCP < Base
    Protocol = 0 # always 0

    def initialize(host, port)
      @host = host
      @port = port
    end

    def close
      @socket&.close
      @socket = nil
    end

    private

    def request(request, &)
      socket = socket()
      transaction = rand(2**16)
      length = request.bytesize
      socket.write [transaction, Protocol, length, request].pack("nnna*")
      header = socket.read(8)
      rtransaction, rprotocol, _response_length, _unit, _function = header.unpack("nnnCC")
      raise "Invalid transaction (#{rtransaction} != #{transaction})" if rtransaction != transaction
      raise "Invalid protocol (#{rprotocol})" if rprotocol != Protocol
      yield
    rescue SocketError => ex
      close
      raise ex
    end

    def read(count)
      @socket.read(count)
    end

    def socket
      @socket ||= Socket.tcp(@host, @port)
    end
  end
end
