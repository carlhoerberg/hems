require "socket"
require "json"

class Devices
  class Shelly
    def self.from_device_id(device_id)
      case device_id
      when /^shellyhtg3-/      then ShellyHTG3.new(device_id)
      when /^shellyplusplugs-/ then ShellyPlusPlugS.new(device_id)
      else                     raise "Unknown device id #{device_id}"
      end
    end

    def initialize
      @udp = UDPSocket.new
      @udp.bind("0.0.0.0", 4913)
      puts "Shelly UDP server listening on #{@udp.local_address.inspect_sockaddr}"
      @devices = {}
      Thread.new { start }
    end

    def plugs
      @devices.each_value.select { |d| Devices::ShellyPlusPlugS === d }
    end

    def termometers
      @devices.each_value.select { |d| Devices::ShellyHTG3 === d }
    end

    def start
      loop do
        json, _from = @udp.recvfrom(4096)
        begin
          p data = JSON.parse(json)
          device = @devices[data["src"]] ||= Shelly.from_device_id(data["src"])
          device.notify_status(data["params"])
        rescue => e
          warn "ShellyUDPServer error: #{e.inspect}", json.inspect
        end
      end
    end
  end

  class ShellyUDP
    @@udp = UDPSocket.new
    @@lock = Mutex.new

    def initialize(host, port)
      @host = host
      @port = port
    end

    def rpc(method, params)
      request = { id: rand(2**16), method:, params:}
      @@lock.synchronize do
        @@udp.send(request.to_json, 0, @host, @port)
        bytes, _from = @@udp.recvfrom(4096)
        response = JSON.parse(bytes)
        raise Error.new("Invalid ID in response") if response["id"] != request[:id]
        raise Error.new(resp.dig("error", "message")) if response["error"]
        response.fetch("result")
      end
    end

    class Error < StandardError; end
  end

  class ShellyPlusPlugS < ShellyUDP
    attr_reader :device_id, :current, :apower, :aenergy_total, :voltage

    def initialize(device_id, port = 1010)
      super(device_id, port)
      @device_id = device_id
      update_status_loop
    end

    def notify_status(params)
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

    private

    def update_status
      s = status
      @current = s["current"]
      @apower = s["apower"]
      @voltage = s["voltage"]
      @aenergy_total = s.dig("aenergy", "total")
    end

    def update_status_loop
      Thread.new do
        Thread.name = "Shelly Plug update status loop #{@device_id}"
        update_status
        sleep 5
      end
    end
  end

  class ShellyHTG3
    attr_reader :device_id, :humidity, :temperature

    def initialize(device_id)
      @device_id = device_id
    end

    def notify_status(params)
      if (h = params.dig("humidity:0", "rh"))
        @humidity = h
      end
      if (t = params.dig("temperature:0", "tC"))
        @temperature = t
      end
    end
  end
end
