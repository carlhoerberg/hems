class HTTPServer
  class HeruControl
    def initialize(heru)
      @heru = heru
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "heru_control.erb")))

    def do_GET(req, res)
      case req.path
      when "/heru/supply_temperature"
        res.content_type = "text/plain"
        res.body = @heru.supply_air_temperature.to_s
      when "/heru/outdoor_temperature"
        res.content_type = "text/plain"
        res.body = @heru.outdoor_temperature.to_s
      else
        res.content_type = "text/html"
        res.body = @@view.result_with_hash({
          modes: @heru.modes,
          alarms: @heru.alarms,
          measurements: @heru.measurements,
          settings: @heru.settings,
        })
      end
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "on" then @heru.on = true
      when "off" then @heru.on = false
      when "boost" then @heru.boost_mode = !@heru.boost_mode?
      when "overpressure" then @heru.overpressure_mode = !@heru.overpressure_mode?
      when "away" then @heru.away_mode = !@heru.away_mode?
      when "clear_alarms" then @heru.clear_alarms
      when "reset_filter_timer" then @heru.reset_filter_timer
      end
      if (v = form["temperature_setpoint"])
        @heru.temperature_setpoint = v.to_i
      end
      if (v = form["supply_fan_speed"])
        @heru.supply_fan_speed = v.to_i
      end
      if (v = form["exhaust_fan_speed"])
        @heru.exhaust_fan_speed = v.to_i
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
