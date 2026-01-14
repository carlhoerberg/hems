class HTTPServer
  class SDMOControl
    def initialize(sdmo)
      @sdmo = sdmo
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "sdmo_control.erb")))

    def do_GET(req, res)
      case req.path
      when %r(/start$)
        @sdmo.start
        res.body = "started"
      when %r(/stop$)
        @sdmo.stop
        res.body = "stopped"
      when %r(/auto$)
        @sdmo.auto
        res.body = "auto"
      else
        res.content_type = "text/html"
        res.body = @@view.result_with_hash({ status: @sdmo.status,
                                             measurements: @sdmo.measurements })
      end
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "start" then @sdmo.start
      when "stop" then @sdmo.stop
      when "auto" then @sdmo.auto
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
