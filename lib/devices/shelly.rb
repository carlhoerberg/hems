require "socket"
require "json"
require "net/http"
require "uri"

class Devices
  class Shelly
    COMPONENT_METRICS = {
      /^switch:\d+$/ => {
        "current" => "shelly_current",
        "voltage" => "shelly_voltage",
        "apower" => "shelly_apower",
        ["aenergy", "total"] => ["shelly_aenergy_total", :counter],
      },
      /^light:\d+$/ => {
        "current" => "shelly_current",
        "voltage" => "shelly_voltage",
        "apower" => "shelly_apower",
        ["aenergy", "total"] => ["shelly_aenergy_total", :counter],
        "brightness" => "shelly_brightness",
        "output" => "shelly_output",
      },
      /^pm1:\d+$/ => {
        "current" => "shelly_current",
        "voltage" => "shelly_voltage",
        "apower" => "shelly_apower",
        ["aenergy", "total"] => ["shelly_aenergy_total", :counter],
      },
      /^em:\d+$/ => {
        "total_current" => "shelly_current",
        "total_act_power" => "shelly_apower",
        "total_aprt_power" => "shelly_aprtpower",
      },
      /^emdata:\d+$/ => {
        "total_act" => ["shelly_aenergy_total", :counter],
      },
      /^em1:\d+$/ => {
        "current" => "shelly_current",
        "voltage" => "shelly_voltage",
        "act_power" => "shelly_apower",
        "aprt_power" => "shelly_aprtpower",
      },
      /^em1data:\d+$/ => {
        "total_act_energy" => ["shelly_aenergy_total", :counter],
      },
      /^temperature:\d+$/ => {
        "tC" => "shelly_temperature",
      },
      /^humidity:\d+$/ => {
        "rh" => "shelly_humidity",
      },
      /^input:\d+$/ => {
        ["counts", "xtotal"] => ["shelly_count", :counter],
      },
    }

    attr_reader :devices, :device_info

    def initialize
      @devices = {}
      @device_info = {}
      fetch_cloud_device_info
      @server = Thread.new { listen }
    end

    private

    def fetch_cloud_device_info
      auth_key = ENV["SHELLY_CLOUD_AUTH_KEY"]
      server = ENV["SHELLY_CLOUD_SERVER"]
      return unless auth_key && server

      uri = URI("https://#{server}/v2/devices/api/get?auth_key=#{auth_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10
      req = Net::HTTP::Post.new(uri)
      req.content_type = "application/json"
      req.body = JSON.generate({ select: ["settings"] })
      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        warn "Shelly Cloud API error: #{res.code} #{res.body}"
        return
      end
      data = JSON.parse(res.body)
      data.each do |device|
        id = device["id"] || next
        settings = device["settings"] || next
        name = settings["name"] || next
        room = settings.dig("room", "name") || next
        @device_info[id] = { name:, room: }
      end
      puts "Shelly Cloud: loaded info for #{@device_info.size} devices"
    rescue => e
      warn "Shelly Cloud API fetch failed: #{e.inspect}"
    end

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
              notify_event(event, data["src"])
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
      matched = false

      params.each_key do |component_key|
        next if component_key == "ts" || component_key == "sys"
        COMPONENT_METRICS.each do |pattern, fields|
          next unless pattern.match?(component_key)
          matched = true
          component_data = params[component_key]
          next unless component_data.is_a?(Hash)

          fields.each do |field_path, metric_def|
            metric_name, type = Array === metric_def ? metric_def : [metric_def, nil]
            v = if Array === field_path
                  component_data.dig(*field_path)
                else
                  component_data[field_path]
                end
            next if v.nil?
            v = v ? 1 : 0 if v == true || v == false
            entry = { v:, ts: }
            entry[:counter] = true if type == :counter
            device["#{metric_name}/#{component_key}"] = entry
          end
        end
      end

      unless matched
        # Ignore known devices without component metrics
        puts "Unknown shelly params: #{device_id} #{params.keys}" unless device_id.match?(/^shelly(blugwg3|1g3)-/)
      end
    end

    def notify_event(event, src)
      data = event["data"]
      ts = (event["ts"] * 1000).to_i
      case event["event"]
      when "aranet"
        device_id = "aranet-#{data["sys"]["addr"].delete(":")}"
        device = @devices[device_id] ||= {}
        if (v = data["co2_ppm"])
          device["aranet_co2_ppm"] = { v:, ts: }
        end
        if (v = data["tC"])
          device["aranet_temperature"] = { v:, ts: }
        end
        if (v = data["rh"])
          device["aranet_humidity"] = { v:, ts: }
        end
        if (v = data["pressure_dPa"])
          device["aranet_pressure"] = { v:, ts: }
        end
        if (v = data["battery"])
          device["aranet_battery"] = { v:, ts: }
        end
      when "shelly-blu"
        device_id = "shellybluht-#{data["address"].delete(":")}"
        device = @devices[device_id] ||= {}
        if (v = data["temperature"])
          if Numeric === v
            device["shelly_temperature"] = {v:, ts:}
          end
        end
        if (v = data["humidity"])
          device["shelly_humidity"] = {v:, ts:}
        end
        if (v = data["battery"])
          device["shelly_battery"] = {v:, ts:}
        end
      end
    end
  end
end
