require "socket"
require "json"

class Devices
  class Shelly
    @@devices = {}
    @@server = Thread.new { Shelly.listen }

    def plugs
      @@devices.each_value.select { |d| d.respond_to?(:apower) }
    end

    def termometers
      @@devices.each_value.select { |d| d.respond_to?(:temperature) }
    end

    def self.listen
      udp = UDPSocket.new
      udp.bind("0.0.0.0", 4913)
      puts "Shelly UDP server listening on #{udp.local_address.inspect_sockaddr}"
      loop do
        json, _from = udp.recvfrom(4096)
        begin
          p data = JSON.parse(json)
          case data["method"]
          when "NotifyStatus", "NotifyFullStatus"
            device = @@devices[data["src"]] ||= Shelly.from_device_id(data["src"])
            device.notify_status(data["params"])
          when "NotifyEvent"
            data.dig("params", "events").each do |event|
              Shelly.notify_event(event)
            end
          end
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
      when /^shellyplugsg3-/   then ShellyPlusPlugS.new(device_id)
      when /^shellyproem50-/   then ShellyProEM50.new(device_id)
      else                     raise "Unknown device id #{device_id}"
      end
    end

    # {"src"=>"shellyplusplugs-fcb4670cf7fc", "dst"=>"*", "method"=>"NotifyEvent", "params"=>{"ts"=>1729713785.0, "events"=>[{"component"=>"script:1", "id"=>1, "event"=>"shelly-blu", "data"=>{"encryption"=>false, "BTHome_version"=>2, "pid"=>82, "battery"=>100, "humidity"=>50, "temperature"=>19.7, "rssi"=>-71, "address"=>"7c:c6:b6:62:46:80"}, "ts"=>1729713785.0}]}}
    #
    # {"src"=>"shellyplusplugs-d4d4daecd810", "dst"=>"*", "method"=>"NotifyEvent", "params"=>{"ts"=>1729893268.8, "events"=>[{"component"=>"script:1", "id"=>1, "event"=>"aranet", "data"=>{"status"=>{"integration"=>true, "dfu"=>false, "cal_state"=>0}, "sys"=>{"fw_patch"=>19, "fw_minor"=>4, "fw_major"=>1, "hw"=>9, "addr"=>"cc:37:b5:bf:d6:a7", "rssi"=>-71}, "region"=>15, "packaging"=>1, "co2_ppm"=>1275, "tC"=>21.6, "pressure_dPa"=>9459, "rh"=>34, "battery"=>93, "co2_aranet_level"=>2, "refresh_interval"=>300, "age"=>4, "packet_counter"=>221}, "ts"=>1729893268.8}]}}
    def self.notify_event(event)
      data = event["data"]
      case event["event"]
      when "aranet"
        device_id = "aranet-#{data["sys"]["addr"].delete(":")}"
        device = @@devices[device_id] ||= Aranet.new device_id
        device.update_data(data, event["ts"])
      when "shelly-blu"
        device_id = "shellybluht-#{data["address"].delete(":")}"
        device = @@devices[device_id] ||= ShellyBluHT.new device_id
        device.update_data(data, event["ts"])
      end
    end
  end

  class ShellyDevice
    attr_reader :ts, :device_id

    def initialize(device_id)
      @device_id = device_id
    end

    def timestamp
      (@ts * 1000).to_i if @ts
    end
  end

  class Aranet < ShellyDevice
    attr_reader :co2_ppm, :temperature, :humidity, :pressure, :battery

    def update_data(data, ts)
      @ts = ts
      @co2_ppm = data["co2_ppm"]
      @temperature = data["tC"]
      @humidity = data["rh"]
      @pressure = data["pressure_dPa"]
      @battery = data["battery"]
    end
  end

  class ShellyBluHT < ShellyDevice
    attr_reader :temperature, :humidity, :battery

    def update_data(data, ts)
      @ts = ts
      if (v = data["temperature"])
        @temperature = v
      end
      if (v = data["humidity"])
        @humidity = v
      end
      if (v = data["battery"])
        @battery = v
      end
    end
  end

  class ShellyUDP < ShellyDevice
    @@udp = UDPSocket.new
    @@lock = Mutex.new

    def initialize(device_id, port)
      super(device_id)
      @port = port
    end

    def rpc(method, params)
      request = { id: rand(2**16), method:, params: }
      @@lock.synchronize do
        @@udp.send(request.to_json, 0, @device_id, @port)
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

  class ShellyProEM50 < ShellyUDP
    attr_reader :current, :apower, :voltage, :aenergy_total

    def initialize(device_id, port = 2020)
      super(device_id, port)
      #update_status
    end

    def notify_status(params)
      if (c = params.dig("em1data:0", "current"))
        @current = c
      end
      if (p = params.dig("em1data:0", "voltage"))
        @voltage = p
      end
      if (p = params.dig("em1data:0", "act_power"))
        @apower = p
      end
      if (p = params.dig("em1data:0", "total_act_energy"))
        @aenergy_total = p
      end
      if ((ts = params.dig("ts")) && @current && @voltage && @apower && @aenergy_total)
        @ts = ts
      end
    end
  end

  class ShellyPlusPlugS < ShellyUDP
    attr_reader :current, :apower, :aenergy_total, :voltage

    def initialize(device_id, port = 1010)
      super(device_id, port)
      update_status
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
      if ((ts = params.dig("ts")) && @current && @voltage && @apower && @aenergy_total)
        @ts = ts
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

  class ShellyHTG3 < ShellyDevice
    attr_reader :humidity, :temperature

    def notify_status(params)
      if (h = params.dig("humidity:0", "rh"))
        @humidity = h
      end
      if (t = params.dig("temperature:0", "tC"))
        @temperature = t
      end
      if ((ts = params.dig("ts")) && @humidity && @temperature)
        @ts = ts
      end
    end
  end
end
