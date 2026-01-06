class HTTPServer
  class GrundfosControl
    def initialize(grundfos)
      @grundfos = grundfos
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "grundfos_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({
        controlmode: @grundfos.controlmode,
        setpoint: @grundfos.setpoint,
        head_setpoint: @grundfos.head_setpoint,
        max_pressure_range: @grundfos.max_pressure_range,
        status: @grundfos.status,
        measurements: @grundfos.measurements,
        counters: @grundfos.counters,
        alarm: @grundfos.alarm,
        warning: @grundfos.warning
      })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "Set control mode"
        @grundfos.controlmode = form["controlmode"].to_i
      when "Set setpoint"
        @grundfos.setpoint = form["setpoint"].to_i
      when "Set head setpoint"
        @grundfos.head_setpoint = form["head_setpoint"].to_f
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
