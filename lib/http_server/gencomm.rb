class HTTPServer
  class GenCommControl
    def initialize(gencomm)
      @gencomm = gencomm
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "gencomm_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({ control_mode: @gencomm.control_mode_name,
                                           status: @gencomm.status,
                                           active_status_flags: @gencomm.active_status_flags,
                                           status_flags: @gencomm.status_flags,
                                           dpf_status: @gencomm.dpf_status,
                                           measurements: @gencomm.measurements,
                                           named_alarms: @gencomm.named_alarms })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "stop" then @gencomm.stop
      when "auto" then @gencomm.auto
      when "manual" then @gencomm.manual
      when "reset_alarms" then @gencomm.reset_alarms
      when "dpf_regen_inhibit_on" then @gencomm.dpf_regen_inhibit_on
      when "dpf_regen_inhibit_off" then @gencomm.dpf_regen_inhibit_off
      when "dpf_regen_start" then @gencomm.dpf_regen_start
      when "dpf_regen_stop" then @gencomm.dpf_regen_stop
      when "clear_telemetry_alarm" then @gencomm.clear_telemetry_alarm
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
