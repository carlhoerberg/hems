class NibeTCP
  def initialize(host, port)
    @host = host
    @port = port
    @values = {
      40004 => { name: "bt1", type: "s", factor: 10.0 }, # outdoor temp
      40008 => { name: "bt2", type: "s", factor: 10.0 }, # supply temp
      40012 => { name: "bt3", type: "s", factor: 10.0 }, # return temp
      40013 => { name: "bt7", type: "s", factor: 10.0 }, # hot water top
      40014 => { name: "bt6", type: "s", factor: 10.0 }, # hot water load
      40025 => { name: "bt20", type: "s", factor: 10.0 }, # exhaust air temp
      40026 => { name: "bt21", type: "s", factor: 10.0 }, # vented air temp
      40051 => { name: "bs1", type: "s", factor: 10.0 }, # air flow (unfiltered)
      40072 => { name: "bf1", type: "s", factor: 10.0 }, # flow
      40321 => { name: "compressor_frequency", type: "S" },
      41256 => { name: "fan_speed", type: "C" },
      43084 => { name: "electrical_addition", type: "s" },
      43416 => { name: "compressor_starts", type: "l", factor: 1 },
      43437 => { name: "pump_speed", type: "C" }, # pump speed
      45001 => { name: "alarm", type: "s" },
    }
  end

  def read_loop
    loop do
      socket = Socket.tcp(@host, @port, connect_timeout: 1)
      loop do
        case socket.readbyte
        when 0x06 # ack
          puts "acked"
        when 0x15 # nack
          raise "nacked"
        when 0x5C # start of msg
          msg = "\x5C" + socket.read(4)
          msg[1] == "\x00" || raise("unknown value")
          msg[2] == "\x20" || raise("not for modbus")
          command = msg[3]
          data_len = msg[4]
          msg << data = socket.read(data_len)
          msg_checksum = socket.readbyte

          if msg_checksum != checksum
            nack(socket)
            next
          end

          case command
          when "\x6B" # write request
            if req = @write_requests.pop(true)
              # construct write msg
              # socket.write(req_msg)
            else
              ack(socket)
            end
          when "\x69" # read request
            last_updated_addr = 0
            min_ts = Time.now.to_i * 2
            @values.each do |addr, v|
              last_updated_addr = addr if v[:ts].nil? || min_ts < v[:ts]
            end
            socket.write read_request(last_updated_addr)
          when "\x6A" # read response
            addr = data.unpack1("N")
            v = @values[addr]
            value = data[2..].unpack1(v[:type])
            v[:value] = value / v[:factor]
            v[:ts] = Time.now.to_i
          else
            puts "command=0x#{command.ord.to_s(16)}"
            puts IO::Buffer.for(data).hexdump
            ack(socket)
          end
        end
      rescue => e
        warn e.message
        break
      end
    end
  end

  def read_request(addr)
    # start of msg, read request, length, 16 bit address, checksum
    msg = [0xC0, 0x69, 0x02, addr].pack("CCCs")
    [checksum(msg)].pack("C", msg)
  end

  def ack(socket)
    socket.putc 0x06
  end

  def nack(socket)
    socket.putc 0x15
  end

  def checksum(data)
    checksum = 0
    data.each_byte { |b| checksum ^= b }
    if checksum == 0x5C
      checksum = 0xC5
    end
    checksum
  end
end
