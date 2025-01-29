class HTTPServer
  class TopasControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, topas)
      super(server)
      @topas = topas
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "views", "topas_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({ configuration: @topas.configuration,
                                           status: @topas.status,
                                           measurements: @topas.measurements })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "reset_alarms" then @topas.reset_alarms
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
