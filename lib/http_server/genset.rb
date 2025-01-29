class HTTPServer
  class GensetControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, genset)
      super(server)
      @genset = genset
    end

    @@view = ERB.new(File.read(File.join(__dir__, "..", "views", "genset_control.erb")))

    def do_GET(req, res)
      case req.path
      when %r(/start$)
        @genset.start
        res.body = "started"
      when %r(/stop$)
        @genset.stop
        res.body = "stopped"
      else
        res.content_type = "text/html"
        res.body = @@view.result_with_hash({ status: @genset.status,
                                             measurements: @genset.measurements })
      end
    end

    def do_POST(req, res)
      form = URI.decode_www_form(req.body).to_h
      case form["action"]
      when "start" then @genset.start
      when "stop" then @genset.stop
      else raise "no action selected"
      end
      res.status = 303
      res["location"] = req.path
    end
  end
end
