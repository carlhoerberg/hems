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
      puts "request #{transaction}"
      @transactions[transaction] = cb
      q = SizedQueue.new(1)
      @responses[transaction] = q
      @socket.write [transaction, Protocol, request.bytesize].pack("nnn"), request
      result = q.pop
      @responses.delete(transaction)
      result
    end

    def read_loop
      loop do
        header = read(8)
        rtransaction, rprotocol, _response_length, _unit, function = header.unpack("nnnCC")
        puts "response #{rtransaction}"
        raise ProtocolException, "Invalid protocol (#{rprotocol})" if rprotocol != Protocol
        check_exception!(function)
        if (cb = @transactions.delete(rtransaction))
          result = cb.call
          @responses[rtransaction] << result
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
