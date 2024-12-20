require "socket"
require "net/protocol"
require_relative "../modbus"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  # https://modbus.org/docs/Modbus_Messaging_Implementation_Guide_V1_0b.pdf
  class TCP < Base
    def initialize(host, port = 502)
      @host = host
      @port = port
      @lock = Mutex.new
    end

    def close
      @socket&.close
      @socket = nil
    end

    private

    Protocol = 0

    def request(request, &)
      try = 0
      transaction = 0 # the waveshare relay have trouble with transactions, rand(2**16)
      @lock.synchronize do
        begin
          socket.write [transaction, Protocol, request.bytesize].pack("nnn"), request
          header = read(8)
          rtransaction, rprotocol, _response_length, _unit, function = header.unpack("nnnCC")
          raise ProtocolException, "Invalid transaction (#{rtransaction} != #{transaction})" if rtransaction != transaction
          raise ProtocolException, "Invalid protocol (#{rprotocol})" if rprotocol != Protocol
          check_exception!(function)
          yield
        rescue SocketError, SystemCallError, IOError, Timeout::Error => ex
          close
          retry if (try += 1) < 2
          raise ex
        rescue ProtocolException => ex
          close
          raise ex
        end
      end
    end

    def read(count, timeout = 10)
      if IO.select([@socket], nil, nil, timeout)
        @socket.read(count) || raise(EOFError.new)
      else
        raise Net::ReadTimeout.new(@socket)
      end
    end

    def socket
      @socket ||= Socket.tcp(@host, @port, connect_timeout: 1)
    end
  end
end
