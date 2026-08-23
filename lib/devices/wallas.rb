require "net/http"
require "json"
require "uri"

class Devices
  # Wallas 40 EA cabin diesel heater, through its 3008 control panel.
  #
  # The panel has no interface over IP and its cloud cannot be impersonated (it
  # validates the server certificate), so everything goes over Bluetooth:
  # bin/wallas_agent runs on a Pi in radio range of the panel, holds the bonded
  # connection and serves the panel's own fields. See the README for the protocol.
  class Wallas
    def initialize(host = "192.168.0.110", port = 8080)
      @agent = URI("http://#{host}:#{port}")
    end

    # Everything the panel reports, nil when the gateway is unreachable
    def state
      http = Net::HTTP.new(@agent.host, @agent.port)
      http.open_timeout = 2
      http.read_timeout = 4
      res = http.get("/state")
      return nil unless res.is_a?(Net::HTTPSuccess)
      state = JSON.parse(res.body)
      state["values"] ? state : nil
    rescue StandardError, JSON::ParserError
      nil
    end

    def values
      state&.fetch("values")
    end

    def room_temperature
      values&.dig("room_temperature")
    end

    def coolant_temperature
      values&.dig("coolant_temperature")
    end

    # 0 = off, 3 = idle/paused
    def heater_state
      values&.dig("state")
    end

    # The panel's own command, "SET RTT=<hundredths of a Kelvin>"
    def target_room_temperature=(celsius)
      post("/set", JSON.generate(target_room_temperature: celsius.to_f))
    end

    def extra_water_pump=(on)
      post("/set", JSON.generate(extra_water_pump: on ? 1 : 0))
    end

    def stop
      post("/stop", "")
    end

    # STOP came out of a capture of the phone app, START is an assumption, so
    # this one is unverified. The panel ignores commands it does not recognise,
    # a wrong verb is a no-op rather than a misfire.
    def start
      post("/start", "")
    end

    def power=(on)
      on ? start : stop
    end

    # Raw command to the panel, for verbs that are not mapped yet
    def command_panel(payload)
      post("/write", payload)
    end

    private

    def post(path, body)
      http = Net::HTTP.new(@agent.host, @agent.port)
      http.open_timeout = 2
      http.read_timeout = 5
      res = http.post(path, body, "Content-Type" => "application/json")
      raise "Wallas agent #{path}: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
      true
    end
  end
end
