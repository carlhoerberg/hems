require "socket"
require "webrick"
require "zlib"

class NibeTCP
  def initialize(host = "192.168.3.134", port = 730)
    @host = host
    @port = port
    @values = {
      40004 => { name: "bt1_outdoor_temp", type: "s<", factor: 10.0 }, # outdoor temp
      40008 => { name: "bt2_supply_temp", type: "s<", factor: 10.0 }, # supply temp
      40012 => { name: "bt3_return_temp", type: "s<", factor: 10.0 }, # return temp
      40013 => { name: "bt7_hot_water_top", type: "s<", factor: 10.0 }, # hot water top
      40014 => { name: "bt6_hot_water_load", type: "s<", factor: 10.0 }, # hot water load
      40025 => { name: "bt20_exhaust_air_temp", type: "s<", factor: 10.0 }, # exhaust air temp
      40026 => { name: "bt21_vented_air_temp", type: "s<", factor: 10.0 }, # vented air temp
      40051 => { name: "bs1_air_flow", type: "s<", factor: 10.0 }, # air flow (unfiltered)
      40072 => { name: "bf1_flow", type: "s<", factor: 10.0 }, # flow
      40321 => { name: "compressor_frequency", type: "S<" },
      43084 => { name: "electrical_addition", type: "s<" },
      43108 => { name: "fan_speed", type: "C" },
      43416 => { name: "compressor_starts", type: "l<" },
      43437 => { name: "pump_speed", type: "C" }, # pump speed
      45001 => { name: "alarm", type: "s<" },
    }
    @server = WEBrick::HTTPServer.new(Port: ENV.fetch("PORT", 6730).to_i,
                                      AccessLog: [])
    @server.mount_proc("/metrics") do |req, res|
      res.content_type = "text/plain"
      updated_values = @values.values.select { |v| v[:ts] }
      metrics = @@nibe.result_with_hash({ values: updated_values })
      if req.accept_encoding.include? "gzip"
        res["content-encoding"] = "gzip"
        res.body = Zlib.gzip(metrics)
      else
        res.body = metrics
      end
    end
    Thread.new { @server.start }
  end

  @@nibe = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "nibe.erb")))

  def read_loop
    loop do
      socket = Socket.tcp(@host, @port, connect_timeout: 1)
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      puts "connected sync=#{socket.sync}"
      loop do
        case byte = socket.readbyte
        when 0x06 # ack
          puts "acked"
        when 0x15 # nack
          puts "nacked"
        when 0x5C # start of msg
          null = socket.readbyte
          if null != 0x0
            puts "unexpected value after 0x5c: 0x#{null.to_s(16)}"
            next
          end
          puts "start_of_msg"
          device = socket.readbyte
          command = socket.readbyte
          data_len = socket.readbyte
          puts "device=0x#{device.to_s(16)} command=0x#{command.to_s(16)} len=#{data_len}"

          data = socket.read(data_len)
          msg_checksum = socket.readbyte
          msg = [device, command, data_len, data].pack("CCCa*")
          calc_checksum = checksum(msg)

          if msg_checksum != calc_checksum
            puts "checksum_mismatch msg=#{msg_checksum.to_s(16)} calc=#{calc_checksum.to_s(16)}"
            puts IO::Buffer.for(data).hexdump unless data.empty?
            nack(socket)
            next
          else
            puts "checksum_valid msg=#{msg_checksum.to_s(16)} calc=#{calc_checksum.to_s(16)}"
          end

          if device != 0x20
            puts "not for modbus, #{device.to_s(16)}"
            puts IO::Buffer.for(data).hexdump unless data.empty?
            ack(socket)
            next
          end

          case command
          when 0x6B # write request
            puts "write_request"
            #if req = @write_requests.pop(true)
            #  # construct write msg
            #  # socket.write(req_msg)
            #else
            #  ack(socket)
            #end
            ack(socket)
          when 0x69 # read request
            last_updated_addr = 0
            min_ts = Time.now.to_f * 1000 + 1000
            @values.each do |addr, v|
              if v[:ts].nil?
                last_updated_addr = addr
                break
              end
              if v[:ts] < min_ts
                last_updated_addr = addr
                min_ts = v[:ts]
              end
            end
            raise "could not find an address to update" if last_updated_addr.zero?
            bytes = read_request(last_updated_addr)
            puts "read_request=\"#{bytes.unpack1("H*")}\" addr=#{last_updated_addr}"
            socket.write bytes
          when 0x6A # read response
            addr = data.unpack1("S<")
            if (v = @values[addr])
              value = data.unpack1(v[:type], offset: 2)
              v[:value] = value / v.fetch(:factor, 1)
              v[:ts] = (Time.now.to_f * 1000).to_i
              puts "read_response addr=#{addr} name=\"#{v[:name]}\" value=#{v[:value]}"
            else
              puts "read_response address_not_found=#{addr}"
            end
            ack(socket)
          else
            puts IO::Buffer.for(data).hexdump unless data.empty?
            ack(socket)
          end
        else
          puts "read_byte=0x#{byte.to_s(16)}"
        end
      end
    end
  end

  def read_request(addr)
    # start of msg, read request, length, 16 bit address, checksum
    msg = [0xC0, 0x69, 0x02, addr].pack("CCCS<")
    [checksum(msg)].pack("C", buffer: msg)
  end

  def ack(socket)
    puts "response=ack"
    socket.putc 0x06
  end

  def nack(socket)
    puts "response=nack"
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

NibeTCP.new.read_loop
