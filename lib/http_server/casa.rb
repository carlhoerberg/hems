class HTTPServer
  class CasaControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, casa)
      super(server)
      @casa = casa
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "casa_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({
        measurements: @casa.measurements,
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
