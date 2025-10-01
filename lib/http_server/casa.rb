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
        operating_mode: @casa.operating_mode
      })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      if (op = form["operating_mode"])
        @casa.operating_mode = op.to_i
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
