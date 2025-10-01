class HTTPServer
  class RelaysControl
    def initialize(relays)
      @relays = relays
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "relays_control.erb")))

    def do_GET(req, res)
      res.content_type = "text/html"
      res.body = @@view.result_with_hash({ status: @relays.status })
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      @relays.toggle(form["id"].to_i)
      res.status = 303
      res["location"] = req.path
    end
  end
end
