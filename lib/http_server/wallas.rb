class HTTPServer
  class WallasControl
    def initialize(wallas)
      @wallas = wallas
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "wallas_control.erb")))

    def do_GET(req, res)
      case req.path
      when "/wallas/room_temperature"
        res.content_type = "text/plain"
        res.body = @wallas.room_temperature.to_s
      when "/wallas/coolant_temperature"
        res.content_type = "text/plain"
        res.body = @wallas.coolant_temperature.to_s
      else
        res.content_type = "text/html"
        res.body = @@view.result_with_hash({ state: @wallas.state })
      end
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "start"
        # Starting runs a glow plug and a five minute ignition, so only with the
        # confirmation ticked.
        @wallas.start if form["confirm"]
      when "stop" then @wallas.stop
      when "extra_water_pump_on" then @wallas.extra_water_pump = true
      when "extra_water_pump_off" then @wallas.extra_water_pump = false
      end
      if (temperature = form["target_room_temperature"])
        @wallas.target_room_temperature = temperature.to_f
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
