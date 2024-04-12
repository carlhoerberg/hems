require "socket"
require "json"
require_relative "./devices/shelly_ht"

class ShellyUDPServer
  def initialize
    @udp = UDPSocket.new
    @udp.bind("0.0.0.0", 4913)
    @devices = {}
  end

  def start
    loop do
      json, _from = @udp.recvfrom(4096)
      begin
        data = JSON.parse(json)
        pp data
        src = data["src"]
        case src
        when /^shellyhtg3-/ # humidity/temperature sensor
          device = @devices.fetch(src)
          if (h = data.dig("params", "humidity:0", "rh"))
            device.humidity = h
          end
          if (t = data.dig("params", "temperature:0", "tC"))
            device.temperature = t
          end
        else
          STDERR.puts "Device not found #{src}", data.inspect
        end
      rescue JSON::JSONError => e
        STDERR.puts "ShellyUDP ERROR: #{e.inspect}", json.inspect
      end
    end
  end

  def stop
    @udp.close
  end

  def register(device)
    @devices[device.device_id] = device
  end
end

maskinrum = Devices::ShellyHT.new("shellyhtg3-543204537d10")
Thread.new do
  loop do
    sleep 5
    puts "temp=#{maskinrum.temperature} humidity=#{maskinrum.humidity}"
  end
end
su = ShellyUDP.new
su.register(maskinrum)
su.start
