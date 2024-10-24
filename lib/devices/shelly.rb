require "socket"
require "json"

class Devices
  class Shelly
    @@devices = {}
    @@server = Thread.new { Shelly.listen }

    def plugs
      @@devices.reject! { |_, s| ShellyPlusPlugS === s && Time.at(s.ts) < Time.now - 180 && p("rejecting", s) }
      @@devices.each_value.grep(ShellyPlusPlugS)
    end

    def termometers
      @@devices.reject! { |_, s| ShellyHTG3 === s && Time.at(s.ts) < Time.now - 600 && p("rejecting", s) }
      @@devices.each_value.grep(ShellyHTG3)
    end

    def self.listen
      udp = UDPSocket.new
      udp.bind("0.0.0.0", 4913)
      puts "Shelly UDP server listening on #{udp.local_address.inspect_sockaddr}"
      loop do
        json, _from = udp.recvfrom(4096)
        begin
          p data = JSON.parse(json)
          device = @@devices[data["src"]] ||= Shelly.from_device_id(data["src"])
          device.notify_status(data["params"])
        rescue => e
          warn "ShellyUDPServer error: #{e.inspect}", json.inspect
          STDERR.puts e.backtrace.join("\n")
        end
      end
    end

    def self.from_device_id(device_id)
      case device_id
      when /^shellyhtg3-/      then ShellyHTG3.new(device_id)
      when /^shellyplusplugs-/ then ShellyPlusPlugS.new(device_id)
      else                     raise "Unknown device id #{device_id}"
      end
    end
  end

  class ShellyUDP
    @@udp = UDPSocket.new
    @@lock = Mutex.new

    attr_reader :ts

    def initialize(host, port)
      @host = host
      @port = port
    end

    def notify_status(params)
      if (ts = params.dig("ts"))
        @ts = ts
      end
    end

    def rpc(method, params)
      request = { id: rand(2**16), method:, params: }
      @@lock.synchronize do
        @@udp.send(request.to_json, 0, @host, @port)
        begin
          bytes, _from = @@udp.recvfrom_nonblock(4096)
          puts "UDP RPC response: #{bytes}"
          response = JSON.parse(bytes)
          raise Error.new("Invalid ID in response") if response["id"] != request[:id]
          raise Error.new(resp.dig("error", "message")) if response["error"]
          response.fetch("result")
        rescue IO::WaitReadable
          IO.select([@@udp], nil, nil, 1) || raise(Error, "Timeout waiting for RPC UDP response")
          retry
        end
      end
    end

    class Error < StandardError; end
  end

  class ShellyPlusPlugS < ShellyUDP
    attr_reader :device_id, :current, :apower, :aenergy_total, :voltage

    def initialize(device_id, port = 1010)
      super(device_id, port)
      @device_id = device_id
      update_status
    end

    def notify_status(params)
      super
      if (c = params.dig("switch:0", "current"))
        @current = c
      end
      if (p = params.dig("switch:0", "voltage"))
        @voltage = p
      end
      if (p = params.dig("switch:0", "apower"))
        @apower = p
      end
      if (p = params.dig("switch:0", "aenergy", "total"))
        @aenergy_total = p
      end
    end

    def status
      rpc("Switch.GetStatus", { id: 0 })
    end

    def switch_on
      rpc("Switch.Set", { id: 0, on: true })
    end

    def switch_off
      rpc("Switch.Set", { id: 0, on: false })
    end

    def reset_counter
      rpc("Switch.ResetCounters", { id: 0, type: ["aenergy"] })
    end

    private

    def update_status
      s = status
      @current = s["current"]
      @apower = s["apower"]
      @voltage = s["voltage"]
      @aenergy_total = s.dig("aenergy", "total")
    end
  end

  class ShellyHTG3
    attr_reader :ts, :device_id, :humidity, :temperature

    def initialize(device_id)
      @device_id = device_id
    end

    def notify_status(params)
      if (ts = params.dig("ts"))
        @ts = ts
      end
      if (h = params.dig("humidity:0", "rh"))
        @humidity = h
      end
      if (t = params.dig("temperature:0", "tC"))
        @temperature = t
      end
    end
  end
end
