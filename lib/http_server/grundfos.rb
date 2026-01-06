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
        operationmode: @grundfos.operationmode,
        setpoint: @grundfos.setpoint,
        head_setpoint: @grundfos.head_setpoint,
        feedback_max: @grundfos.feedback_max,
        feedback_unit: @grundfos.feedback_unit,
        feedback_sensor: @grundfos.feedback_sensor,
        process_feedback: @grundfos.process_feedback,
        status: @grundfos.status,
        measurements: @grundfos.measurements,
        counters: @grundfos.counters,
        alarm: @grundfos.alarm,
        alarm_name: @grundfos.alarm_name,
        warning: @grundfos.warning,
        warning_name: @grundfos.warning_name,
        device_info: @grundfos.device_info,
        pi_controller: @grundfos.pi_controller,
      })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "Set control mode"
        @grundfos.controlmode = form["controlmode"].to_i
      when "Set operation mode"
        @grundfos.operationmode = form["operationmode"].to_i
      when "Set setpoint"
        @grundfos.setpoint = form["setpoint"].to_f
      when "Set head setpoint"
        @grundfos.head_setpoint = form["head_setpoint"].to_f
      when "Turn On"
        @grundfos.pump_on = true
      when "Turn Off"
        @grundfos.pump_on = false
      when "Set Remote"
        @grundfos.remote_control = true
      when "Set Local"
        @grundfos.remote_control = false
      when "Reset Alarm"
        @grundfos.reset_alarm
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
