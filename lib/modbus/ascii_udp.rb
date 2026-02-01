require "socket"
require_relative "../modbus"

# Modbus ASCII over UDP protocol
# Used by Chauvin Arnoux / AEMC PEL 103 power loggers
# https://modbus.org/docs/Modbus_over_serial_line_V1_02.pdf (Section 2.5)
module Modbus
  class AsciiUDP < Base
    def initialize(host, port = 80, timeout: 3)
      @host = host
      @port = port
      @timeout = timeout
      @lock = Mutex.new
    end

    def close
      @socket&.close
      @socket = nil
    end

    private

    def request(request)
      try = 0
      @lock.synchronize do
        begin
          # Encode request as Modbus ASCII: :AABBCCDD...LRC\r\n
          hex = request.unpack1("H*").upcase
          lrc = calc_lrc(hex)
          message = ":#{hex}#{lrc}\r\n"

          socket.send(message, 0, @host, @port)

          # Read response
          response_ascii, = socket.recvfrom(1024)
          @response_binary = decode_ascii_response(response_ascii)

          @response_pos = 0
          unit, function = read(2).unpack("CC")
          request_unit, request_function = request[0..1].unpack("CC")
          raise ProtocolException, "Invalid unit response (#{unit} != #{request_unit})" if unit != request_unit
          raise ProtocolException, "Invalid function response (#{function} != #{request_function})" if function != request_function
          check_exception!(function)
          yield
        rescue SocketError, SystemCallError, IOError, Timeout::Error, ProtocolException => ex
          close
          retry if (try += 1) < 2
          raise ex
        end
      end
    end

    def read(count)
      result = @response_binary[@response_pos, count]
      raise EOFError, "Not enough data in response" if result.nil? || result.length < count
      @response_pos += count
      result
    end

    def socket
      @socket ||= begin
        sock = UDPSocket.new
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [@timeout, 0].pack("l_2"))
        sock
      end
    end

    def calc_lrc(hex_string)
      lrc = 0
      hex_string.scan(/../).each { |byte| lrc = (lrc + byte.to_i(16)) & 0xFF }
      lrc = ((lrc ^ 0xFF) + 1) & 0xFF
      format("%02X", lrc)
    end

    def decode_ascii_response(ascii)
      # Format: :AABBCCDD...LRC\r\n
      ascii = ascii.strip
      raise ProtocolException, "Invalid response start" unless ascii.start_with?(":")

      # Strip : prefix and LRC suffix (last 2 chars)
      hex_data = ascii[1..-3]

      # Verify LRC
      expected_lrc = ascii[-2..-1]
      actual_lrc = calc_lrc(hex_data)
      raise ProtocolException, "LRC mismatch (#{actual_lrc} != #{expected_lrc})" if actual_lrc != expected_lrc

      # Decode hex to binary
      [hex_data].pack("H*")
    end
  end
end
