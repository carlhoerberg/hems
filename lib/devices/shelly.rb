require "socket"
require "json"

class Devices
  class Shelly
    # Example
    # @devices = {
    #   "deviceid" => {
    #     "shelly_temp" => { value: 123, ts: 11111111, counter: false },
    #   }
    # }
    attr_reader :devices

    def initialize
      @devices = {}
      @server = Thread.new { listen }
    end

    private

    def listen
      udp = UDPSocket.new
      udp.bind("0.0.0.0", 4913)
      puts "Shelly UDP server listening on #{udp.local_address.inspect_sockaddr}"
      loop do
        json, _from = udp.recvfrom(4096)
        begin
          data = JSON.parse(json)
          case data["method"]
          when "NotifyStatus", "NotifyFullStatus"
            notify_status(data["src"], data["params"])
          when "NotifyEvent"
            data.dig("params", "events").each do |event|
              notify_event(event)
            end
          end
        rescue => e
          warn "ShellyUDPServer error: #{e.inspect}", json.inspect
          STDERR.puts e.backtrace.join("\n")
        end
      end
    end

    def notify_status(device_id, params)
      ts = (params["ts"] * 1000).to_i
      device = @devices[device_id] ||= {}
      case device_id
      when /^shellyhtg3-/
        if (v = params.dig("humidity:0", "rh"))
          device["shelly_ht_humidity"] = { v:, ts: }
        end
        if (v = params.dig("temperature:0", "tC"))
          device["shelly_ht_temperature"] = { v:, ts: }
        end
      when /^shellyplusplugs-/, /^shellyplugsg3-/, /^shelly2pmg3-/
        if (v = params.dig("switch:0", "current"))
          device["shelly_plug_current"] = { v:, ts: }
        end
        if (v = params.dig("switch:0", "voltage"))
          device["shelly_plug_voltage"] = { v:, ts: }
        end
        if (v = params.dig("switch:0", "apower"))
          device["shelly_plug_apower"] = { v:, ts: }
        end
        if (v = params.dig("switch:0", "aenergy", "total"))
          device["shelly_plug_aenergy_total"] = { v:, ts:, counter: true }
        end
      when /^shellyproem50-/
        if (v = params.dig("em1:0", "current"))
          device["shelly_plug_current"] = { v:, ts: }
        end
        if (v = params.dig("em1:0", "voltage"))
          device["shelly_plug_voltage"] = { v:, ts: }
        end
        if (v = params.dig("em1:0", "act_power"))
          device["shelly_plug_apower"] = { v:, ts: }
        end
        if (v = params.dig("em1:0", "aprt_power"))
          device["shelly_plug_aprtpower"] = { v:, ts: }
        end
        if (v = params.dig("em1data:0", "total_act_energy"))
          device["shelly_plug_aenergy_total"] = { v:, ts:, counter: true }
        end
      when /^shellypro3em-/
        if (v = params.dig("em:0", "total_current"))
          device["shelly_plug_current"] = { v:, ts: }
        end
        if (v = params.dig("em:0", "total_act_power"))
          device["shelly_plug_apower"] = { v:, ts: }
        end
        if (v = params.dig("em:0", "total_aprt_power"))
          device["shelly_plug_aprtpower"] = { v:, ts: }
        end
        if (v = params.dig("emdata:0", "total_act"))
          device["shelly_plug_aenergy_total"] = { v:, ts:, counter: true }
        end
      else raise "Unknown device id #{device_id}"
      end
    end

    # {"src"=>"shellyplusplugs-fcb4670cf7fc", "dst"=>"*", "method"=>"NotifyEvent", "params"=>{"ts"=>1729713785.0, "events"=>[{"component"=>"script:1", "id"=>1, "event"=>"shelly-blu", "data"=>{"encryption"=>false, "BTHome_version"=>2, "pid"=>82, "battery"=>100, "humidity"=>50, "temperature"=>19.7, "rssi"=>-71, "address"=>"7c:c6:b6:62:46:80"}, "ts"=>1729713785.0}]}}
    #
    # {"src"=>"shellyplusplugs-d4d4daecd810", "dst"=>"*", "method"=>"NotifyEvent", "params"=>{"ts"=>1729893268.8, "events"=>[{"component"=>"script:1", "id"=>1, "event"=>"aranet", "data"=>{"status"=>{"integration"=>true, "dfu"=>false, "cal_state"=>0}, "sys"=>{"fw_patch"=>19, "fw_minor"=>4, "fw_major"=>1, "hw"=>9, "addr"=>"cc:37:b5:bf:d6:a7", "rssi"=>-71}, "region"=>15, "packaging"=>1, "co2_ppm"=>1275, "tC"=>21.6, "pressure_dPa"=>9459, "rh"=>34, "battery"=>93, "co2_aranet_level"=>2, "refresh_interval"=>300, "age"=>4, "packet_counter"=>221}, "ts"=>1729893268.8}]}}
    def notify_event(event)
      data = event["data"]
      ts = (event["ts"] * 1000).to_i
      case event["event"]
      when "aranet"
        device_id = "aranet-#{data["sys"]["addr"].delete(":")}"
        device = @devices[device_id] ||= {}
        if (v = data["co2_ppm"])
          device[:aranet_co2_ppm] = { v:, ts: }
        end
        if (v = data["tC"])
          device[:aranet_temperature] = { v:, ts: }
        end
        if (v = data["rh"])
          device[:aranet_humidity] = { v:, ts: }
        end
        if (v = data["pressure_dPa"])
          device[:aranet_pressure] = { v:, ts: }
        end
        if (v = data["battery"])
          device[:aranet_battery] = { v:, ts: }
        end
      when "shelly-blu"
        device_id = "shellybluht-#{data["address"].delete(":")}"
        device = @devices[device_id] ||= {}
        if (v = data["temperature"])
          if Numeric === v
            device[:shelly_ht_temperature] = {v:, ts:}
          else
            p event
          end
        end
        if (v = data["humidity"])
          device[:shelly_ht_humidity] = {v:, ts:}
        end
        if (v = data["battery"])
          device[:shelly_ht_battery] = {v:, ts:}
        end
      end
    end
  end
end
