require "net/http"
require "json"
require "uri"
require "time"

class Devices
  # Wallas 40 EA cabin diesel heater, through its 3008 control panel.
  #
  # The panel has no local interface, it only uploads to iotwallas.net over
  # HTTPS every few minutes and takes its commands from there, so this reads the same
  # API the "Wallas Remote" link opens. Set WALLAS_LINK to that link, it carries
  # the client token:
  #   https://iotwallas.net/api2/r.php?<base64 of client=...&params=...>
  #
  # The panel's cloud cannot be impersonated (it validates the server
  # certificate), but it does talk Bluetooth locally, so bin/wallas_agent runs on
  # a Pi in radio range and serves the panel's own fields over HTTP. Point
  # WALLAS_AGENT at it (http://host:8080) and that becomes the source, with the
  # cloud as fallback for the fields the BLE protocol has not been mapped to yet.
  # See the README.
  class Wallas
    # Measurements the panel uploads, each fetched separately
    TYPES = {
      heaterstate: :string,
      roomtemp: :float,
      watertemp: :float,
      burnertemp: :float,
      burnerfanrpm: :integer,
      power: :integer,
      supplyvolt: :float,
      targetroomtemp: :integer,
      targetwatertemp: :integer,
      runtime: :float,
      starts: :integer,
      errorcode: :integer,
    }.freeze

    def initialize(link = ENV["WALLAS_LINK"], agent: ENV["WALLAS_AGENT"])
      @agent = URI(agent) unless agent.nil? || agent.empty?
      unless link.nil? || link.empty?
        @uri = URI(link)
        @base = @uri.path.sub(%r{/[^/]*\z}, "")
        @http = Net::HTTP.new(@uri.host, @uri.port || 443)
        @http.use_ssl = true
        @http.open_timeout = 5
        @http.read_timeout = 10
      end
      raise ArgumentError, "WALLAS_AGENT or WALLAS_LINK is required" if @agent.nil? && @uri.nil?
      @lock = Mutex.new
    end

    # Whether the cloud API is configured, the BLE gateway alone is enough
    def cloud?
      !@uri.nil?
    end

    # State from the local BLE gateway, nil when it is not configured or down so
    # that callers fall back to the cloud
    def local
      return nil unless @agent
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

    def measurements
      @lock.synchronize do
        TYPES.to_h do |type, cast|
          value, = latest(type)
          [type, convert(value, cast)]
        end
      end
    end

    # When the panel last uploaded, it goes quiet for minutes at a time
    def updated_at
      @lock.synchronize do
        _, date = latest(:roomtemp)
        date && Time.parse(date)
      end
    end

    def heater_state
      convert(latest_locked(:heaterstate).first, :string)
    end

    def room_temperature
      convert(latest_locked(:roomtemp).first, :float)
    end

    def water_temperature
      convert(latest_locked(:watertemp).first, :float)
    end

    def error_code
      convert(latest_locked(:errorcode).first, :integer)
    end

    # Set the room target through the local gateway. The panel's own command,
    # read off the phone app: "SET RTT=<hundredths of a Kelvin>".
    def target_room_temperature=(celsius)
      raise "WALLAS_AGENT is not configured" unless @agent
      post_agent("/set", JSON.generate(target_room_temperature: celsius.to_f))
    end

    # Raw command to the panel, for commands not mapped yet
    def command_panel(payload)
      raise "WALLAS_AGENT is not configured" unless @agent
      post_agent("/write", payload)
    end

    # Stop the heater. The panel's own STOP command through the gateway, or the
    # cloud when there is no gateway.
    def stop
      return post_agent("/stop", "") if @agent
      command("action" => "onoff", "action_id" => "5", "onoff" => "off")
    end

    # Starting has to go through the cloud for now, the BLE start command has not
    # been captured. Same call the vendor's page makes after its safety
    # confirmation, and it needs internet.
    def power=(on)
      return stop unless on
      command("action" => "onoff", "action_id" => "5", "onoff" => "on")
    end

    def extra_water_pump=(on)
      return post_agent("/set", JSON.generate(extra_water_pump: on ? 1 : 0)) if @agent
      command("extra_water_pump" => (on ? "1" : "0"))
    end

    private

    def post_agent(path, body)
      http = Net::HTTP.new(@agent.host, @agent.port)
      http.open_timeout = 2
      http.read_timeout = 5
      res = http.post(path, body, "Content-Type" => "application/json")
      raise "Wallas agent #{path}: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
      true
    end

    def latest_locked(type)
      @lock.synchronize { latest(type) }
    end

    # Latest value and timestamp of one measurement, [value, date] or [nil, nil].
    # The panel can be quiet for a long time, so widen the window when the short
    # one comes back empty.
    def latest(type, ranges = ["1h", "24h"])
      ranges.each do |range|
        body = request(Net::HTTP::Post.new("#{@base}/ajax/ajax_dots_influxdb.php?type=#{type}&range=#{range}"))
        points = JSON.parse(body)
        point = points.reverse.find { _1["value"] }
        return [point["value"], point["date"]] if point
      end
      [nil, nil]
    rescue JSON::ParserError
      [nil, nil]
    end

    def command(params)
      post = Net::HTTP::Post.new("#{@base}/save.php")
      post.set_form_data(params)
      request(post)
    end

    # The session comes from opening the remote link, renew it when it expires
    def request(req, retried = false)
      req["Cookie"] = session
      res = @http.request(req)
      if res.is_a?(Net::HTTPSuccess) && !res.body.to_s.empty?
        res.body
      elsif retried
        raise "Unexpected response from #{req.path}: #{res.code} #{res.body.to_s[0, 100]}"
      else
        @session = nil
        request(req, true)
      end
    end

    def session
      @session ||= begin
        res = @http.request(Net::HTTP::Get.new(@uri.request_uri))
        cookie = res.get_fields("set-cookie")&.find { _1.start_with?("PHPSESSID") }
        raise "No session cookie from #{@uri.path}: #{res.code}" unless cookie
        cookie.split(";").first
      end
    end

    def convert(value, cast)
      return nil if value.nil?
      case cast
      when :float then Float(value)
      when :integer then Integer(value, exception: false) || Float(value).round
      else value
      end
    end
  end
end
