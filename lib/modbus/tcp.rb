require "socket"
require_relative "../modbus"

# https://modbus.org/docs/Modbus_Application_Protocol_V1_1b.pdf
module Modbus
  # https://modbus.org/docs/Modbus_Messaging_Implementation_Guide_V1_0b.pdf
  class TCP < Base
    def initialize(host, port = 502)
      @host = host
      @port = port
      @socket = Socket.tcp(@host, @port)
      @transactions = {}
      @responses = {}
      @lock = Mutex.new
      Thread.new { read_loop }
    end

    def close
      @socket&.close
      @socket = nil
    end

    private

    Protocol = 0

    def request(request, &cb)
      transaction = rand(2**16)
      q = SizedQueue.new(1)
      @lock.synchronize do
        @transactions[transaction] = cb
        @responses[transaction] = q
      end
      @socket.write [transaction, Protocol, request.bytesize].pack("nnn"), request
      result = q.pop
      @lock.synchronize { @responses.delete(transaction) }
      result
    end

    def read_loop
      loop do
        header = read(8)
        rtransaction, rprotocol, _response_length, _unit, function = header.unpack("nnnCC")
        raise ProtocolException, "Invalid protocol (#{rprotocol})" if rprotocol != Protocol
        check_exception!(function)
        if (cb = @lock.synchronize { @transactions.delete(rtransaction) })
          result = cb.call
          @lock.synchronize { @responses[rtransaction] << result }
        else
          raise "No request callback for transaction #{rtransaction} #{@transactions.inspect}"
        end
      end
    end

    def read(count)
      @socket.read(count) || raise(EOFError.new)
    end
  end
end
