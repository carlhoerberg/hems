class HTTPServer
  class ETAControl
    def initialize(eta)
      @eta = eta
    end

    def do_GET(req, res)
      case req.path
      when %r(/stop$)
        @eta.stop_boilers
      when %r(/menu$)
        res.content_type = "application/xml"
        res.body = @eta.menu
      else
        res.status = 404
        res.body = "Not Found"
      end
    end
  end
end
