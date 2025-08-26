class HTTPServer
  class ETAControl < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, eta)
      super(server)
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
        raise WEBrick::HTTPStatus::NotFound
      end
    end
  end
end
