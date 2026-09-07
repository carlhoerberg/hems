class HTTPServer
  class CasaControl
    def initialize(casa)
      @casa = casa
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "casa_control.erb")))

    def do_GET(req, res)
      if req.path == "/casa/supply_temperature"
        res.content_type = "text/plain"
        res.body = @casa.supply_air_temperature_before_heater.to_s
        return
      end

      res.content_type = "text/html"
      res.body = @@view.result_with_hash({
        measurements: @casa.measurements,
        status: @casa.status,
        operating_mode: @casa.operating_mode,
        fireplace_active: @casa.fireplace_active,
        fireplace_level: @casa.fireplace_level,
        timed_function_time_left: @casa.timed_function_time_left
      })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      if (op = form["operating_mode"])
        @casa.operating_mode = op.to_i
      end
      # Set the overpressure level before starting, so the run uses it
      if (level = form["fireplace_level"])
        @casa.fireplace_level = level.to_i
      end
      case form["action"]
      when "start_fireplace" then @casa.fireplace_active = true
      when "stop_fireplace" then @casa.fireplace_active = false
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
